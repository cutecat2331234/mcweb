# frozen_string_literal: true

require "test_helper"

module Minecraft
  class IdentityLifecycleContributorsTest < ActiveSupport::TestCase
    test "CE catalogs register the Minecraft lifecycle contributors" do
      assert_includes ::Identity::DataExportCatalog.entries.map(&:key), "minecraft.accounts"
      assert_includes ::Identity::AccountClosureCatalog.entries.map(&:key),
                      "minecraft.identity_bindings"
    end

    test "data export allowlists only the user's bindings and public identity facts" do
      user = create_user
      other_user = create_user
      staff = create_user(account_type: :staff, username: "private_staff_name")
      current_link, current_identity = create_bound_account(
        user:,
        username: "CurrentPlayer",
        metadata: { "private_marker" => "metadata-secret" },
        skin_texture_url: "https://private.example/skin-token"
      )
      historical_link, = create_bound_account(user:, username: "HistoricPlayer", active: false)
      target_link, = create_bound_account(user:, username: "TargetPlayer")
      other_link, other_identity = create_bound_account(user: other_user, username: "OtherPlayer")

      current_identity.skin_texture_file.attach(
        io: StringIO.new("binary-skin-secret"),
        filename: "skin.png",
        content_type: "image/png"
      )
      Minecraft::SkinRefreshRequest.create!(
        player_identity: current_identity,
        requested_by: staff,
        status: "failed",
        idempotency_key_digest: Digest::SHA256.hexdigest("skin-request"),
        trigger: "manual",
        error_code: "raw-task-error-secret"
      )
      create_pending_primary_request(
        user:,
        source: current_link,
        target: target_link,
        requested_by: staff,
        reason: "private-staff-workflow-reason"
      )
      Minecraft::Identity.create!(
        user:,
        player_profile: current_link.player_profile,
        uuid: current_identity.external_uuid,
        username: current_identity.username,
        identity_type: "java",
        linked_at: current_link.linked_at,
        metadata: { "legacy_private" => "legacy-metadata-secret" },
        skin_texture_url: "https://private.example/legacy-skin-token"
      )
      legacy_profile = Minecraft::PlayerProfile.create!(metadata: { "private" => "profile-secret" })
      legacy_public_identity = Minecraft::PlayerIdentity.create!(
        player_profile: legacy_profile,
        platform: "java",
        external_uuid: SecureRandom.uuid,
        username: "LegacyOnlyPlayer",
        identity_type: "java",
        valid_from: 4.days.ago,
        metadata: { "private" => "identity-secret" }
      )
      Minecraft::Identity.create!(
        user:,
        player_profile: legacy_profile,
        uuid: legacy_public_identity.external_uuid,
        username: legacy_public_identity.username,
        identity_type: "java",
        linked_at: 3.days.ago,
        metadata: { "private" => "legacy-only-secret" }
      )
      server = create_server
      Minecraft::LinkCode.create!(
        server:,
        code_digest: "verification-secret-digest",
        minecraft_uuid: current_identity.external_uuid,
        minecraft_username: current_identity.username,
        identity_type: "java",
        expires_at: 1.hour.from_now,
        used_at: Time.current,
        used_by: user
      )

      contribution = Minecraft::IdentityLifecycle::DataExportContributor.call(
        context: ::Identity::DataExporting::Context.new(user:, generated_at: Time.current)
      )
      accounts = contribution.documents.fetch("minecraft/accounts.json")
      json = JSON.generate(accounts)

      assert_equal 4, accounts.length
      current = accounts.find { |account| account["player_id"] == current_link.player_profile.public_id }
      assert_equal %w[binding_type identity linked_at player_id primary_account unlinked_at],
                   current.keys.sort
      assert_equal %w[external_uuid identity_type platform username valid_from],
                   current.fetch("identity").keys.sort
      assert_equal true, current.fetch("primary_account")
      historical = accounts.find do |account|
        account["player_id"] == historical_link.player_profile.public_id
      end
      assert_not_nil historical.fetch("unlinked_at")
      assert_equal 1, accounts.count { |account| account["binding_type"] == "legacy_identity" }
      assert_includes json, "LegacyOnlyPlayer"

      refute_includes json, other_link.player_profile.public_id
      refute_includes json, other_identity.external_uuid
      %w[
        metadata-secret binary-skin-secret raw-task-error-secret
        private-staff-workflow-reason private_staff_name verification-secret-digest
        legacy-metadata-secret legacy-skin-token profile-secret identity-secret
      ].each { |secret| refute_includes json, secret }
    end

    test "data export succeeds deterministically for an unbound user" do
      user = create_user
      context = ::Identity::DataExporting::Context.new(user:, generated_at: Time.current)

      first = Minecraft::IdentityLifecycle::DataExportContributor.call(context:)
      second = Minecraft::IdentityLifecycle::DataExportContributor.call(context:)

      assert_equal [], first.documents.fetch("minecraft/accounts.json")
      assert_equal first.documents, second.documents
      assert_equal 0, first.record_count
    end

    test "preflight blocks an active player session without mutating bindings" do
      user = create_user
      link, = create_bound_account(user:, username: "OnlinePlayer")
      Minecraft::PlayerSession.create!(
        player_profile: link.player_profile,
        server: create_server,
        username: "OnlinePlayer",
        joined_at: Time.current,
        source: "test"
      )

      result = contributor.preflight(context: closure_context(user))

      assert_predicate result, :blocked?
      assert_equal "minecraft_account_close_active_session", result.code
      assert_nil link.reload.unlinked_at
      assert_predicate link, :primary_account?
    end

    test "preflight surfaces a downstream unlink restriction without internal data" do
      user = create_user
      link, = create_bound_account(user:, username: "RestrictedPlayer")
      denial = ServiceResult.failure(
        error: :edition_identity_unlink_active_workflow,
        code: :edition_identity_unlink_active_workflow,
        value: { internal_record_id: 999, task_error: "secret" }
      )

      result = Minecraft::IdentityUnlinkRestrictions.stub(:check, denial) do
        contributor.preflight(context: closure_context(user))
      end

      assert_predicate result, :blocked?
      assert_equal "edition_identity_unlink_active_workflow", result.code
      assert_equal({ "outcome" => "identity_unlink_restricted", "affected_bindings" => 1 },
                   result.details)
      assert_nil link.reload.unlinked_at
    end

    test "execution revokes user bindings and preserves shared Minecraft facts" do
      user = create_user
      first_link, first_identity = create_bound_account(user:, username: "FirstPlayer")
      second_link, = create_bound_account(user:, username: "SecondPlayer")
      request_record = create_pending_primary_request(
        user:,
        source: first_link,
        target: second_link,
        requested_by: user,
        reason: "Switch primary"
      )
      event = Minecraft::PrimaryAccountChangeEvent.create!(
        user:,
        from_identity_link: nil,
        to_identity_link: first_link,
        actor: user,
        change_source: "player_immediate",
        idempotency_key_digest: Digest::SHA256.hexdigest("initial-primary"),
        counts_for_cooldown: true,
        changed_at: 2.days.ago
      )
      legacy = Minecraft::Identity.create!(
        user:,
        player_profile: first_link.player_profile,
        uuid: first_identity.external_uuid,
        username: first_identity.username,
        identity_type: "java",
        linked_at: first_link.linked_at
      )
      first_identity.skin_texture_file.attach(
        io: StringIO.new("retained-skin"),
        filename: "skin.png",
        content_type: "image/png"
      )
      attachment_id = first_identity.skin_texture_file.attachment.id
      hold = DataGovernance::RetentionHold.create!(
        target: first_link.player_profile,
        created_by: user,
        status: "active",
        reason: "Retain shared player evidence"
      )
      context = closure_context(user)
      preflight = contributor.preflight(context:)

      assert_predicate preflight, :ready?
      assert_equal 1, preflight.details.fetch("retained_obligations")
      execution = contributor.execute(context:, preflight:)

      assert_predicate execution, :completed?
      assert_empty Minecraft::IdentityLink.active.where(user:)
      assert_empty Minecraft::IdentityLink.where(user:, primary_account: true)
      assert_predicate request_record.reload, :cancelled?
      assert_equal "account_closed", request_record.decision_reason
      assert_not Minecraft::Identity.exists?(legacy.id)
      assert Minecraft::PlayerProfile.exists?(first_link.player_profile_id)
      assert Minecraft::PlayerIdentity.exists?(first_identity.id)
      assert ActiveStorage::Attachment.exists?(attachment_id)
      assert Minecraft::PrimaryAccountChangeEvent.exists?(event.id)
      assert DataGovernance::RetentionHold.exists?(hold.id)

      replay_preflight = contributor.preflight(context:)
      replay = contributor.execute(context:, preflight: replay_preflight)
      assert_predicate replay, :completed?
      assert_equal "minecraft_bindings_already_revoked", replay.details.fetch("outcome")
      assert_equal 0, replay.details.fetch("revoked_bindings")
    end

    test "a later contributor failure compensates exact binding state" do
      user = create_user
      first_link, first_identity = create_bound_account(user:, username: "FirstPlayer")
      second_link, = create_bound_account(user:, username: "SecondPlayer")
      request_record = create_pending_primary_request(
        user:,
        source: first_link,
        target: second_link,
        requested_by: user,
        reason: "Switch primary"
      )
      legacy = Minecraft::Identity.create!(
        user:,
        player_profile: first_link.player_profile,
        uuid: first_identity.external_uuid,
        username: first_identity.username,
        identity_type: "java",
        linked_at: first_link.linked_at,
        metadata: { "restored" => true }
      )
      original = {
        first: first_link.attributes.slice("unlinked_at", "primary_account", "lock_version", "updated_at"),
        second: second_link.attributes.slice("unlinked_at", "primary_account", "lock_version", "updated_at"),
        request: request_record.attributes.slice(
          "status", "decided_by_id", "decision_reason", "resolved_at", "applied_at",
          "lock_version", "updated_at"
        )
      }
      failing = failing_contributor
      entries = [
        ::Identity::AccountClosureRegistry::Entry.new(
          key: "minecraft.identity_bindings",
          contributor:
        ),
        ::Identity::AccountClosureRegistry::Entry.new(key: "sample.failure", contributor: failing)
      ]

      result = ::Identity::AccountClosure::Lifecycle.call(
        context: closure_context(user),
        entries:
      )

      assert_predicate result, :failure?
      assert_equal "account_close_contributor_failed", result.code
      assert_equal original.fetch(:first),
                   first_link.reload.attributes.slice(*original.fetch(:first).keys)
      assert_equal original.fetch(:second),
                   second_link.reload.attributes.slice(*original.fetch(:second).keys)
      assert_equal original.fetch(:request),
                   request_record.reload.attributes.slice(*original.fetch(:request).keys)
      assert_predicate first_link, :primary_account?
      assert_predicate request_record, :pending?
      restored_legacy = Minecraft::Identity.find(legacy.id)
      assert_equal({ "restored" => true }, restored_legacy.metadata)
      compensation = result.value.fetch(:contributions)
        .fetch("compensations").fetch("minecraft.identity_bindings")
      assert_equal "compensated", compensation.fetch("status")
    end

    test "the account-close service commits the Minecraft contribution once and replays it" do
      user = create_user
      link, identity = create_bound_account(user:, username: "ClosingPlayer")
      legacy = Minecraft::Identity.create!(
        user:,
        player_profile: link.player_profile,
        uuid: identity.external_uuid,
        username: identity.username,
        identity_type: "java",
        linked_at: link.linked_at
      )

      result = ::Identity::CloseAccount.call(
        user:,
        password: "password123",
        confirmation: "DELETE",
        closure_mode: "anonymize",
        reason: "Close my account"
      )

      assert_predicate result, :success?, result.error
      assert_predicate user.reload, :deleted?
      assert_not_nil user.account_closed_at
      assert_not_nil link.reload.unlinked_at
      refute_predicate link, :primary_account?
      assert_not Minecraft::Identity.exists?(legacy.id)
      contribution = user.account_closure_results.fetch("minecraft.identity_bindings")
      assert_equal "completed", contribution.fetch("status")
      assert_equal "minecraft_bindings_revoked", contribution.dig("details", "outcome")

      replay = ::Identity::CloseAccount.call(
        user:,
        password: "no-longer-checked",
        confirmation: "DELETE",
        closure_mode: "anonymize"
      )
      assert_predicate replay, :success?
      assert_equal true, replay.value.fetch(:replayed)
      assert_equal 1, AuditLog.where(action: "identity.account_closed", resource_id: user.id).count
    end

    private

    def contributor
      Minecraft::IdentityLifecycle::AccountClosureContributor
    end

    def closure_context(user)
      ::Identity::AccountClosure::Context.new(
        user:,
        closure_mode: "anonymize",
        reason: "test closure",
        at: Time.current.change(usec: 123_456)
      )
    end

    def create_bound_account(user:, username:, active: true, metadata: {}, skin_texture_url: nil)
      profile = Minecraft::PlayerProfile.create!
      identity = Minecraft::PlayerIdentity.create!(
        player_profile: profile,
        platform: "java",
        external_uuid: SecureRandom.uuid,
        username:,
        identity_type: "java",
        valid_from: 5.days.ago,
        metadata:,
        skin_texture_url:
      )
      link = Minecraft::IdentityLink.create!(
        user:,
        player_profile: profile,
        linked_at: 4.days.ago,
        unlinked_at: active ? nil : 1.day.ago
      )
      [ link, identity ]
    end

    def create_pending_primary_request(user:, source:, target:, requested_by:, reason:)
      Minecraft::PrimaryAccountChangeRequest.create!(
        user:,
        source_identity_link: source,
        target_identity_link: target,
        requested_by:,
        status: "pending",
        policy_snapshot: "staff_approval",
        idempotency_key_digest: Digest::SHA256.hexdigest(SecureRandom.uuid),
        request_reason: reason,
        requested_at: 1.hour.ago,
        expires_at: 2.days.from_now
      )
    end

    def create_server
      Minecraft::Server.create!(
        name: "Lifecycle test #{SecureRandom.hex(4)}",
        address: "127.0.0.1",
        port: 25_565
      )
    end

    def failing_contributor
      Object.new.tap do |candidate|
        candidate.define_singleton_method(:preflight) do |context:|
          ::Identity::AccountClosure::Contribution.ready(details: { at: context.at.iso8601 })
        end
        candidate.define_singleton_method(:execute) do |**|
          ::Identity::AccountClosure::Contribution.failed(code: "injected_failure")
        end
        candidate.define_singleton_method(:compensate) do |**|
          ::Identity::AccountClosure::Contribution.compensated
        end
      end
    end
  end
end

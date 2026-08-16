# frozen_string_literal: true

require "test_helper"

module Minecraft
  class UnlinkIdentityTest < ActiveSupport::TestCase
    setup do
      @user = create_user
      @first_link = create_bound_account(user: @user, username: "FirstAccount")
      @second_link = create_bound_account(user: @user, username: "SecondAccount")
    end

    test "owner unlink is soft idempotent audited and preserves successor and request cancellation" do
      SiteSetting.set("minecraft.primary_account.switch_policy", "staff_approval")
      SiteSetting.set("minecraft.primary_account.cooldown_seconds", "0")
      SiteSetting.set("minecraft.primary_account.request_expiry_hours", "72")
      requested = Minecraft::RequestPrimaryAccountChange.call(
        user: @user,
        target_identity_link: @second_link,
        actor: @user,
        reason: "Use the second account",
        idempotency_key: "pending-before-unlink"
      )
      request_record = requested.value.fetch(:request)

      result = unlink(@first_link, confirmation: "FirstAccount", key: "unlink-first")

      assert_predicate result, :success?, result.error
      assert_equal true, result.value.fetch(:changed)
      assert_not_nil @first_link.reload.unlinked_at
      assert_predicate @second_link.reload, :primary_account?
      assert_predicate request_record.reload, :cancelled?
      assert_equal [ request_record.id ], result.value.fetch(:cancelled_request_ids)

      audit = AuditLog.find_by!(action: "minecraft.identity_unlinked")
      assert_equal @user, audit.actor
      assert_equal @first_link.id, audit.metadata.fetch("identity_link_id")
      assert_equal "FirstAccount", audit.metadata.fetch("username")
      assert_equal @second_link.id, audit.metadata.fetch("successor_identity_link_id")
      assert_equal [ request_record.id ], audit.metadata.fetch("cancelled_primary_account_request_ids")

      replay = unlink(@first_link, confirmation: "FirstAccount", key: "unlink-first", lock_version: 0)
      assert_predicate replay, :success?, replay.error
      assert_equal true, replay.value.fetch(:replayed)
      assert_equal false, replay.value.fetch(:changed)
      assert_equal 1, AuditLog.where(action: "minecraft.identity_unlinked").count
    end

    test "service enforces owner active target exact confirmation and optimistic lock" do
      outsider = create_user
      forbidden = unlink(@first_link, actor: outsider, confirmation: "FirstAccount", key: "forbidden")
      assert_equal "minecraft_identity_unlink_forbidden", forbidden.code

      foreign_link = create_bound_account(user: outsider, username: "Foreign")
      not_bound = unlink(foreign_link, confirmation: "Foreign", key: "foreign")
      assert_equal "minecraft_identity_unlink_account_not_bound", not_bound.code

      mismatch = unlink(@first_link, confirmation: "firstaccount", key: "mismatch")
      assert_equal "minecraft_identity_unlink_confirmation_mismatch", mismatch.code

      stale_version = @first_link.lock_version
      @first_link.touch
      stale = unlink(
        @first_link,
        confirmation: "FirstAccount",
        key: "stale",
        lock_version: stale_version
      )
      assert_equal "minecraft_identity_unlink_stale", stale.code
      assert_nil @first_link.reload.unlinked_at

      success = unlink(@first_link, confirmation: "FirstAccount", key: "active")
      assert_predicate success, :success?
      inactive = unlink(@first_link, confirmation: "FirstAccount", key: "different-key")
      assert_equal "minecraft_identity_unlink_inactive", inactive.code
    end

    test "service requires confirmation version and idempotency and rejects key reuse for another link" do
      missing_confirmation = unlink(@first_link, confirmation: "", key: "missing-confirmation")
      assert_equal "minecraft_identity_unlink_confirmation_required", missing_confirmation.code

      missing_version = unlink(
        @first_link,
        confirmation: "FirstAccount",
        key: "missing-version",
        lock_version: nil
      )
      assert_equal "minecraft_identity_unlink_lock_version_required", missing_version.code

      missing_key = unlink(@first_link, confirmation: "FirstAccount", key: "")
      assert_equal "minecraft_identity_unlink_idempotency_required", missing_key.code

      assert_predicate unlink(@first_link, confirmation: "FirstAccount", key: "one-use-key"), :success?
      conflict = unlink(@second_link, confirmation: "SecondAccount", key: "one-use-key")
      assert_equal "minecraft_identity_unlink_idempotency_conflict", conflict.code
      assert_nil @second_link.reload.unlinked_at
    end

    test "registered product restriction vetoes before any local state changes" do
      denial = ServiceResult.failure(
        error: :example_identity_unlink_active_workflow,
        code: :example_identity_unlink_active_workflow
      )

      Minecraft::IdentityUnlinkRestrictions.stub(:check, denial) do
        result = unlink(@first_link, confirmation: "FirstAccount", key: "restricted")

        assert_same denial, result
      end

      assert_nil @first_link.reload.unlinked_at
      assert_nil @first_link.unlink_idempotency_key_digest
      assert_not AuditLog.exists?(action: "minecraft.identity_unlinked")
    end

    test "every CE unlink failure code is localized in both product locales" do
      codes = %i[
        minecraft_identity_unlink_forbidden
        minecraft_identity_unlink_account_not_bound
        minecraft_identity_unlink_inactive
        minecraft_identity_unlink_lock_version_required
        minecraft_identity_unlink_stale
        minecraft_identity_unlink_confirmation_required
        minecraft_identity_unlink_confirmation_mismatch
        minecraft_identity_unlink_idempotency_required
        minecraft_identity_unlink_idempotency_conflict
        minecraft_identity_unlink_target_unavailable
        minecraft_identity_unlink_restriction_unavailable
        minecraft_identity_unlink_conflict
      ]

      I18n.available_locales.each do |locale|
        codes.each do |code|
          key = "mcweb.services.errors.#{code}"
          assert I18n.exists?(key, locale: locale), "missing #{locale}.#{key}"
          refute_equal code.to_s, I18n.t(key, locale: locale)
        end
      end
    end

    private

    def unlink(link, confirmation:, key:, actor: @user, lock_version: link.lock_version)
      Minecraft::UnlinkIdentity.call(
        user: @user,
        identity_link: link,
        actor: actor,
        confirmation: confirmation,
        lock_version: lock_version,
        idempotency_key: key,
        ip_address: "192.0.2.10",
        user_agent: "McWeb test"
      )
    end

    def create_bound_account(user:, username:)
      profile = Minecraft::PlayerProfile.create!
      Minecraft::PlayerIdentity.create!(
        player_profile: profile,
        platform: "java",
        external_uuid: SecureRandom.uuid,
        username: username,
        identity_type: "java",
        valid_from: Time.current
      )
      Minecraft::IdentityLink.create!(user: user, player_profile: profile, linked_at: Time.current)
    end
  end
end

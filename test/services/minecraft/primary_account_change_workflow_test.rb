# frozen_string_literal: true

require "test_helper"

module Minecraft
  class PrimaryAccountChangeWorkflowTest < ActiveSupport::TestCase
    setup do
      @user = create_user
      SiteSetting.set("minecraft.primary_account.switch_policy", "immediate")
      SiteSetting.set("minecraft.primary_account.cooldown_seconds", "0")
      SiteSetting.set("minecraft.primary_account.request_expiry_hours", "72")
    end

    test "player immediate switch is local atomic audited and idempotent" do
      first_link = create_bound_account(user: @user, username: "First")
      second_link = create_bound_account(user: @user, username: "Second")
      assert_predicate first_link, :primary_account?
      refute_predicate second_link, :primary_account?

      result = RequestPrimaryAccountChange.call(
        user: @user,
        target_identity_link: second_link,
        actor: @user,
        reason: "Prefer this account",
        idempotency_key: "player-switch-1"
      )

      assert_predicate result, :success?, result.error
      assert_predicate second_link.reload, :primary_account?
      refute_predicate first_link.reload, :primary_account?
      event = PrimaryAccountChangeEvent.find_by!(user: @user)
      assert_equal "player_immediate", event.change_source
      assert_equal first_link, event.from_identity_link
      assert_equal second_link, event.to_identity_link
      audit = AuditLog.find_by!(action: "minecraft.primary_account_changed")
      assert_equal @user.id, audit.metadata.fetch("user_id")

      SiteSetting.set("minecraft.primary_account.cooldown_seconds", "3600")

      replay = RequestPrimaryAccountChange.call(
        user: @user,
        target_identity_link: second_link,
        actor: @user,
        reason: "Prefer this account",
        idempotency_key: "player-switch-1"
      )
      assert_predicate replay, :success?
      assert_equal true, replay.value.fetch(:replayed)
      assert_equal 1, PrimaryAccountChangeEvent.where(user: @user).count
    end

    test "a new immediate switch is blocked during cooldown" do
      first_link = create_bound_account(user: @user, username: "First")
      second_link = create_bound_account(user: @user, username: "Second")
      third_link = create_bound_account(user: @user, username: "Third")
      SiteSetting.set("minecraft.primary_account.cooldown_seconds", "3600")

      first = request_change(second_link, key: "cooldown-first")
      assert_predicate first, :success?

      blocked = request_change(third_link, key: "cooldown-second")
      assert_predicate blocked, :failure?
      assert_equal "primary_account_cooldown_active", blocked.code
      assert_operator blocked.value.fetch(:cooldown_remaining_seconds), :>, 0
      assert_predicate second_link.reload, :primary_account?
      refute_predicate first_link.reload, :primary_account?
      refute_predicate third_link.reload, :primary_account?
    end

    test "database constraint keeps one active primary per user" do
      first_link = create_bound_account(user: @user, username: "First")
      second_link = create_bound_account(user: @user, username: "Second")

      assert_raises(ActiveRecord::RecordNotUnique, ActiveRecord::StatementInvalid) do
        Minecraft::IdentityLink.transaction(requires_new: true) do
          second_link.update_columns(primary_account: true)
        end
      end

      assert_predicate first_link.reload, :primary_account?
      refute_predicate second_link.reload, :primary_account?
    end

    test "staff approval request is idempotent reviewed audited and notified" do
      first_link = create_bound_account(user: @user, username: "First")
      second_link = create_bound_account(user: @user, username: "Second")
      reviewer = create_reviewer
      SiteSetting.set("minecraft.primary_account.switch_policy", "staff_approval")

      requested = request_change(
        second_link,
        key: "approval-request",
        reason: "Use my tournament account"
      )
      assert_predicate requested, :success?, requested.error
      request_record = requested.value.fetch(:request)
      assert_predicate request_record, :pending?
      assert_equal first_link, request_record.source_identity_link
      assert_equal second_link, request_record.target_identity_link
      assert Notification.exists?(
        user: @user,
        notification_type: "minecraft.primary_account.requested"
      )
      assert Notification.exists?(
        user: reviewer,
        notification_type: "minecraft.primary_account.review_required"
      )

      replay = request_change(
        second_link,
        key: "approval-request",
        reason: "Use my tournament account"
      )
      assert_predicate replay, :success?
      assert_equal true, replay.value.fetch(:replayed)
      assert_equal request_record, replay.value.fetch(:request)

      approved = DecidePrimaryAccountChangeRequest.call(
        request_record: request_record,
        actor: reviewer,
        action: "approve",
        reason: "Binding verified",
        lock_version: request_record.lock_version,
        idempotency_key: "approval-decision"
      )
      assert_predicate approved, :success?, approved.error
      assert_predicate request_record.reload, :approved?
      assert_predicate second_link.reload, :primary_account?
      assert_equal "staff_approval", approved.value.fetch(:event).change_source
      assert AuditLog.exists?(action: "minecraft.primary_account_change_approved")
      assert Notification.exists?(
        user: @user,
        notification_type: "minecraft.primary_account.approved"
      )

      decision_replay = DecidePrimaryAccountChangeRequest.call(
        request_record: request_record,
        actor: reviewer,
        action: "approve",
        reason: "Binding verified",
        lock_version: request_record.lock_version,
        idempotency_key: "approval-decision"
      )
      assert_predicate decision_replay, :success?
      assert_equal true, decision_replay.value.fetch(:replayed)
      assert_equal 1, PrimaryAccountChangeEvent.where(primary_account_change_request: request_record).count
    end

    test "approval enforces reason authorization optimistic lock and target validity" do
      create_bound_account(user: @user, username: "First")
      second_link = create_bound_account(user: @user, username: "Second")
      reviewer = create_reviewer
      outsider = create_user
      SiteSetting.set("minecraft.primary_account.switch_policy", "staff_approval")

      missing_reason = request_change(second_link, key: "reason-required", reason: "")
      assert_equal "primary_account_reason_required", missing_reason.code

      requested = request_change(second_link, key: "stale-request", reason: "Please switch")
      request_record = requested.value.fetch(:request)
      stale_version = request_record.lock_version
      request_record.touch

      unauthorized = DecidePrimaryAccountChangeRequest.call(
        request_record: request_record,
        actor: outsider,
        action: "approve",
        reason: "",
        lock_version: request_record.lock_version,
        idempotency_key: "unauthorized-decision"
      )
      assert_equal "primary_account_forbidden", unauthorized.code

      stale = DecidePrimaryAccountChangeRequest.call(
        request_record: request_record,
        actor: reviewer,
        action: "approve",
        reason: "",
        lock_version: stale_version,
        idempotency_key: "stale-decision"
      )
      assert_equal "primary_account_request_stale", stale.code
      assert_predicate request_record.reload, :pending?

      second_link.unlink!
      assert_predicate request_record.reload, :cancelled?
      invalid_target = DecidePrimaryAccountChangeRequest.call(
        request_record: request_record,
        actor: reviewer,
        action: "approve",
        reason: "",
        lock_version: request_record.lock_version,
        idempotency_key: "unlinked-target"
      )
      assert_equal "primary_account_request_not_pending", invalid_target.code
    end

    test "requester can cancel pending request with optimistic locking" do
      create_bound_account(user: @user, username: "First")
      second_link = create_bound_account(user: @user, username: "Second")
      SiteSetting.set("minecraft.primary_account.switch_policy", "staff_approval")
      request_record = request_change(
        second_link,
        key: "cancel-request",
        reason: "Changed my mind later"
      ).value.fetch(:request)

      outsider = create_user
      forbidden = CancelPrimaryAccountChangeRequest.call(
        request_record: request_record,
        actor: outsider,
        lock_version: request_record.lock_version
      )
      assert_equal "primary_account_forbidden", forbidden.code

      cancelled = CancelPrimaryAccountChangeRequest.call(
        request_record: request_record,
        actor: @user,
        lock_version: request_record.lock_version
      )
      assert_predicate cancelled, :success?
      assert_predicate request_record.reload, :cancelled?

      replay = CancelPrimaryAccountChangeRequest.call(
        request_record: request_record,
        actor: @user,
        lock_version: request_record.lock_version
      )
      assert_predicate replay, :success?
      assert_equal true, replay.value.fetch(:replayed)
    end

    test "expired requests are immutable outcomes and do not change the primary" do
      first_link = create_bound_account(user: @user, username: "First")
      second_link = create_bound_account(user: @user, username: "Second")
      SiteSetting.set("minecraft.primary_account.switch_policy", "staff_approval")
      request_record = request_change(
        second_link,
        key: "expiry-request",
        reason: "Temporary request"
      ).value.fetch(:request)
      request_record.update_columns(
        requested_at: 2.minutes.ago,
        expires_at: 1.minute.ago
      )

      result = ExpirePrimaryAccountChangeRequests.call(user: @user)
      assert_predicate result, :success?
      assert_equal 1, result.value.fetch(:expired_count)
      assert_predicate request_record.reload, :expired?
      assert_predicate first_link.reload, :primary_account?
      refute_predicate second_link.reload, :primary_account?
      assert_equal false, request_record.update(decision_reason: "mutated")
      assert_equal "request_expired", request_record.reload.decision_reason
    end

    test "unlinking a primary records an automatic successor without starting cooldown" do
      first_link = create_bound_account(user: @user, username: "First")
      second_link = create_bound_account(user: @user, username: "Second")
      third_link = create_bound_account(user: @user, username: "Third")
      SiteSetting.set("minecraft.primary_account.cooldown_seconds", "3600")

      first_link.unlink!

      event = PrimaryAccountChangeEvent.find_by!(
        user: @user,
        change_source: "automatic_successor"
      )
      assert_equal first_link, event.from_identity_link
      assert_equal second_link, event.to_identity_link
      assert_equal false, event.counts_for_cooldown
      assert_predicate second_link.reload, :primary_account?
      assert_equal 0, PrimaryAccountPolicy.snapshot(user: @user).cooldown_remaining_seconds
      audit = AuditLog.find_by!(action: "minecraft.primary_account_changed", request_id: "minecraft-primary-successor-#{event.id}")
      assert_equal "automatic_successor", audit.metadata.fetch("change_source")

      switched = request_change(third_link, key: "after-successor")
      assert_predicate switched, :success?, switched.error
      assert_predicate third_link.reload, :primary_account?
      assert_equal false, event.update(reason: "mutated")
      assert_equal "primary_account_unlinked", event.reload.reason
    end

    test "administrator-only policy blocks players while a separately authorized override is audited" do
      first_link = create_bound_account(user: @user, username: "First")
      second_link = create_bound_account(user: @user, username: "Second")
      third_link = create_bound_account(user: @user, username: "Third")
      administrator = create_user(account_type: :admin)
      SiteSetting.set("minecraft.primary_account.switch_policy", "administrator_only")
      SiteSetting.set("minecraft.primary_account.cooldown_seconds", "3600")

      blocked = request_change(second_link, key: "player-blocked")
      assert_equal "primary_account_administrator_only", blocked.code

      no_permission = AdministratorSetPrimaryAccount.call(
        user: @user,
        target_identity_link: second_link,
        actor: administrator,
        reason: "Verified support request",
        idempotency_key: "admin-no-permission"
      )
      assert_equal "primary_account_forbidden", no_permission.code

      grant_permission(administrator, "minecraft.primary_accounts.switch_for_user")
      administrator.reload
      no_reason = AdministratorSetPrimaryAccount.call(
        user: @user,
        target_identity_link: second_link,
        actor: administrator,
        reason: "",
        idempotency_key: "admin-no-reason"
      )
      assert_equal "primary_account_reason_required", no_reason.code

      changed = AdministratorSetPrimaryAccount.call(
        user: @user,
        target_identity_link: second_link,
        actor: administrator,
        reason: "Verified support request",
        idempotency_key: "admin-switch"
      )
      assert_predicate changed, :success?, changed.error
      event = changed.value.fetch(:event)
      assert_equal "administrator_override", event.change_source
      assert_equal false, event.counts_for_cooldown
      assert_equal "Verified support request", event.reason
      assert_predicate second_link.reload, :primary_account?
      refute_predicate first_link.reload, :primary_account?
      assert Notification.exists?(
        user: @user,
        notification_type: "minecraft.primary_account.administrator_override"
      )

      SiteSetting.set("minecraft.primary_account.switch_policy", "immediate")
      switched = request_change(third_link, key: "after-admin-override")
      assert_predicate switched, :success?, switched.error
      assert_predicate third_link.reload, :primary_account?
    end

    private

    def request_change(target_link, key:, reason: "Prefer this account")
      RequestPrimaryAccountChange.call(
        user: @user,
        target_identity_link: target_link,
        actor: @user,
        reason: reason,
        idempotency_key: key
      )
    end

    def create_reviewer
      reviewer = create_user(account_type: :staff)
      grant_permission(reviewer, "admin.access")
      grant_permission(reviewer, "minecraft.primary_accounts.review")
      grant_admin_module(reviewer, "minecraft")
      reviewer
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
      Minecraft::IdentityLink.create!(
        player_profile: profile,
        user: user,
        linked_at: Time.current
      )
    end
  end
end

# frozen_string_literal: true

require "test_helper"

module DataGovernance
  class RetentionLifecycleTest < ActiveSupport::TestCase
    setup do
      @actor = create_user
      @user = create_user
    end

    test "active hold blocks deletion and release is audited and idempotent" do
      placed = DataGovernance::PlaceRetentionHold.call(
        target: @user,
        actor: @actor,
        reason: "Preserve records for an active dispute.",
        policy_reference: "CASE-42",
        request_id: "hold-request-1"
      )

      assert placed.success?
      hold = placed.value.fetch(:hold)
      assert_predicate hold, :effective?
      policy = DataGovernance::DeletionPolicy.call(target: @user)
      refute policy.value.fetch(:allowed)
      assert_includes policy.value.fetch(:blockers), "legal_hold"

      released = DataGovernance::ReleaseRetentionHold.call(
        hold:,
        actor: @actor,
        reason: "The dispute is fully resolved.",
        request_id: "hold-release-1"
      )
      replay = DataGovernance::ReleaseRetentionHold.call(
        hold:,
        actor: @actor,
        reason: "The dispute is fully resolved.",
        request_id: "hold-release-1"
      )

      assert released.success?
      refute released.value.fetch(:replayed)
      assert replay.value.fetch(:replayed)
      assert_predicate hold.reload, :released?
      assert_equal 1, AuditLog.where(
        action: "data_governance.retention_hold_released",
        metadata: { hold_public_id: hold.public_id }
      ).count
    end

    test "retention matrix installs every governed resource type" do
      DataGovernance::RetentionPolicy.ensure_defaults!

      assert_equal DataGovernance::RetentionPolicy::DEFAULTS.size, DataGovernance::RetentionPolicy.count
      report_policy = DataGovernance::RetentionPolicy.find_by!(resource_type: "Community::Report")
      refute report_policy.user_deletable?
      assert_nil report_policy.retention_days
    end
  end
end

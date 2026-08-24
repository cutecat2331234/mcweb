# frozen_string_literal: true

require "test_helper"

module Minecraft
  class PlayerAccessRuleLifecycleTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @actor = create_user(account_type: :admin)
      @server = Minecraft::Server.create!(
        name: "Access rule server #{SecureRandom.hex(4)}",
        status: :online,
        last_heartbeat_at: Time.current,
        connector_secret: "secret_#{SecureRandom.hex(16)}"
      )
    end

    test "whitelist apply and revoke queue only fixed connector commands" do
      apply_result = apply_rule(
        rule_type: "whitelist",
        username: "Example_Player",
        reason: "Approved community member",
        idempotency_key: "whitelist-apply-#{SecureRandom.uuid}"
      )

      assert_predicate apply_result, :success?
      rule = apply_result.value.fetch(:rule)
      assert_predicate rule, :pending_apply?
      assert_equal [ "whitelist add Example_Player" ], rule.apply_task.payload.fetch("commands")

      rule.apply_task.complete!("success" => true)
      assert_predicate rule.reload, :active?

      revoke_result = Minecraft::SetPlayerAccessRule.call(
        server: @server,
        actor: @actor,
        desired_state: false,
        rule: rule,
        reason: "Access is no longer required",
        idempotency_key: "whitelist-revoke-#{SecureRandom.uuid}",
        expected_lock_version: rule.lock_version
      )

      assert_predicate revoke_result, :success?
      assert_equal [ "whitelist remove Example_Player" ], rule.reload.revoke_task.payload.fetch("commands")
      rule.revoke_task.complete!("success" => true)
      assert_predicate rule.reload, :revoked?
    end

    test "ban apply is idempotent and a failed revoke remains active" do
      key = "ban-apply-#{SecureRandom.uuid}"
      first = apply_rule(
        rule_type: "ban",
        username: "UnsafePlayer",
        reason: "Repeated griefing",
        idempotency_key: key
      )
      assert_predicate first, :success?
      rule = first.value.fetch(:rule)
      assert_equal [ "ban UnsafePlayer Repeated griefing" ], rule.apply_task.payload.fetch("commands")

      assert_no_difference -> { Minecraft::ConnectorTask.count } do
        replay = apply_rule(
          rule_type: "ban",
          username: "UnsafePlayer",
          reason: "Repeated griefing",
          idempotency_key: key
        )
        assert_predicate replay, :success?
        assert_equal rule, replay.value.fetch(:rule)
        assert replay.value.fetch(:replayed)
      end

      rule.apply_task.complete!("success" => true)
      rule.reload
      revoke = Minecraft::SetPlayerAccessRule.call(
        server: @server,
        actor: @actor,
        desired_state: false,
        rule: rule,
        reason: "Appeal accepted",
        idempotency_key: "ban-revoke-#{SecureRandom.uuid}",
        expected_lock_version: rule.lock_version
      )
      assert_predicate revoke, :success?
      assert_equal [ "pardon UnsafePlayer" ], rule.reload.revoke_task.payload.fetch("commands")

      rule.revoke_task.fail!("error" => "connector rejected command")
      assert_predicate rule.reload, :active?
      assert rule.failed_at.present?
    end

    test "invalid targets and command-breaking reasons fail before connector delivery" do
      assert_no_difference -> { Minecraft::PlayerAccessRule.count } do
        assert_no_difference -> { Minecraft::ConnectorTask.count } do
          invalid_target = apply_rule(
            rule_type: "ban",
            username: "Bad Player",
            reason: "Invalid target",
            idempotency_key: "invalid-target-#{SecureRandom.uuid}"
          )
          assert_predicate invalid_target, :failure?

          invalid_reason = apply_rule(
            rule_type: "ban",
            username: "ValidPlayer",
            reason: "first line\nsecond line",
            idempotency_key: "invalid-reason-#{SecureRandom.uuid}"
          )
          assert_predicate invalid_reason, :failure?
        end
      end
    end

    test "expiry uses the same audited revoke lifecycle" do
      expires_at = 5.minutes.from_now
      result = apply_rule(
        rule_type: "whitelist",
        username: "TemporaryUser",
        reason: "Temporary event access",
        expires_at: expires_at,
        idempotency_key: "temporary-apply-#{SecureRandom.uuid}"
      )
      rule = result.value.fetch(:rule)
      rule.apply_task.complete!("success" => true)

      travel_to(expires_at + 1.second) do
        @server.heartbeat!
        Minecraft::ExpirePlayerAccessRulesJob.perform_now
      end

      assert_predicate rule.reload, :pending_revoke?
      assert_equal "configured_expiry_reached", rule.revoke_reason
      assert_equal [ "whitelist remove TemporaryUser" ], rule.revoke_task.payload.fetch("commands")
    end

    private

    def apply_rule(rule_type:, username:, reason:, idempotency_key:, expires_at: nil)
      Minecraft::SetPlayerAccessRule.call(
        server: @server,
        actor: @actor,
        desired_state: true,
        rule_type: rule_type,
        username: username,
        reason: reason,
        expires_at: expires_at,
        idempotency_key: idempotency_key
      )
    end
  end
end

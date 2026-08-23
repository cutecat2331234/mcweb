# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  class MinecraftPlayerAccessRulesTest < ActionDispatch::IntegrationTest
    setup do
      @operator = create_user(account_type: :admin)
      grant_permission(@operator, "admin.access")
      grant_permission(@operator, "minecraft.servers.control")
      grant_admin_module(@operator, "minecraft")
      @server = ::Minecraft::Server.create!(
        name: "Access admin #{SecureRandom.hex(4)}",
        status: :online,
        last_heartbeat_at: Time.current,
        connector_secret: "secret_#{SecureRandom.hex(16)}"
      )
      sign_in_as(@operator)
    end

    test "operator can inspect and apply a bounded access rule" do
      get admin_minecraft_player_access_rules_path

      assert_response :success
      assert_equal "Admin/Minecraft/PlayerAccessRules/Index", inertia.component
      props = inertia.props.deep_symbolize_keys
      assert_equal @server.public_id, props.fetch(:servers).first.fetch(:id)
      assert_equal %w[whitelist ban], props.fetch(:ruleTypes)

      assert_difference -> { ::Minecraft::PlayerAccessRule.count }, 1 do
        post admin_minecraft_player_access_rules_path, params: {
          access_rule: {
            server_id: @server.public_id,
            rule_type: "ban",
            username: "RuleTarget",
            reason: "Verified abuse",
            idempotency_key: "admin-create-#{SecureRandom.uuid}"
          }
        }
      end

      assert_redirected_to admin_minecraft_player_access_rules_path
      rule = ::Minecraft::PlayerAccessRule.last
      assert_equal [ "ban RuleTarget Verified abuse" ], rule.apply_task.payload.fetch("commands")
    end

    test "operator revocation requires the current optimistic version" do
      result = ::Minecraft::SetPlayerAccessRule.call(
        server: @server,
        actor: @operator,
        desired_state: true,
        rule_type: "ban",
        username: "RuleTarget",
        reason: "Verified abuse",
        idempotency_key: "admin-revoke-setup-#{SecureRandom.uuid}"
      )
      rule = result.value.fetch(:rule)
      rule.apply_task.complete!("success" => true)
      rule.reload

      delete admin_minecraft_player_access_rule_path(rule), params: {
        reason: "Decision reversed",
        lock_version: rule.lock_version + 1,
        idempotency_key: "admin-revoke-stale-#{SecureRandom.uuid}"
      }

      assert_redirected_to admin_minecraft_player_access_rules_path
      assert_predicate rule.reload, :active?
      assert_nil rule.revoke_task

      delete admin_minecraft_player_access_rule_path(rule), params: {
        reason: "Decision reversed",
        lock_version: rule.lock_version,
        idempotency_key: "admin-revoke-valid-#{SecureRandom.uuid}"
      }

      assert_redirected_to admin_minecraft_player_access_rules_path
      assert_predicate rule.reload, :pending_revoke?
      assert_equal [ "pardon RuleTarget" ], rule.revoke_task.payload.fetch("commands")
    end

    test "users without the control permission cannot reach the workflow" do
      delete identity_session_path
      outsider = create_user(account_type: :admin)
      grant_permission(outsider, "admin.access")
      grant_admin_module(outsider, "minecraft")
      sign_in_as(outsider)

      get admin_minecraft_player_access_rules_path

      assert_redirected_to admin_root_path
    end
  end
end

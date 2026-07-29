# frozen_string_literal: true

require "test_helper"

class Identity::AccountAccessTest < ActiveSupport::TestCase
  MODULE_PERMISSIONS = {
    "forum.points.manage" => "forum",
    "identity.groups.read" => "identity",
    "store.fulfillments.read" => "store",
    "system.plugins.manage" => "system",
    "minecraft.nodes.manage" => "minecraft",
    "minecraft.servers.control" => "minecraft",
    "minecraft.players.view" => "minecraft"
  }.freeze

  test "fine grained controller permissions independently unlock their admin module" do
    MODULE_PERMISSIONS.each do |permission, module_key|
      user = create_user
      grant_permission(user, permission)

      assert Identity::AccountAccess.module_allowed?(user, module_key),
        "#{permission} should unlock the #{module_key} admin module"
      assert_includes Identity::AccountAccess::ADMIN_MODULES.fetch(module_key), permission
    end
  end

  test "every active admin module can be granted to staff" do
    assert_equal(
      Identity::AccountAccess.admin_module_keys.sort,
      AdminModuleGrant::MODULE_KEYS.sort
    )
  end

  test "staff identity access requires and accepts the identity module grant" do
    staff = create_user(account_type: "staff")
    grant_permission(staff, "admin.access")
    grant_permission(staff, "identity.groups.read")

    assert_not Identity::AccountAccess.module_allowed?(staff, "identity")

    grant_admin_module(staff, "identity")

    assert Identity::AccountAccess.module_allowed?(staff, "identity")
    assert Identity::AccountAccess.can_access_admin?(staff)
  end

  test "allowed module keys expose the effective navigation scope for every account type" do
    owner = create_user(account_type: "owner")
    staff = create_user(account_type: "staff")
    legacy_member = create_user
    grant_admin_module(staff, "identity")
    grant_permission(staff, "admin.access")
    grant_permission(legacy_member, "admin.access")
    grant_permission(legacy_member, "forum.points.manage")

    assert_equal Identity::AccountAccess.admin_module_keys,
      Identity::AccountAccess.allowed_module_keys(owner)
    assert_equal [ "identity" ], Identity::AccountAccess.allowed_module_keys(staff)
    assert_equal [ "forum" ], Identity::AccountAccess.allowed_module_keys(legacy_member)
    assert_includes Identity::AccountAccess.effective_permission_keys(legacy_member),
      "forum.points.manage"
  end

  test "allowed module lookup does not perform one permission query per catalog entry" do
    legacy_member = create_user
    grant_permission(legacy_member, "admin.access")
    grant_permission(legacy_member, "forum.points.manage")

    queries = []
    subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
      sql = payload[:sql].to_s
      queries << sql unless payload[:name] == "SCHEMA" || sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK)/)
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      assert_equal [ "forum" ], Identity::AccountAccess.allowed_module_keys(legacy_member)
    end

    assert_operator queries.length, :<=, 8,
      "module navigation should resolve from bounded permission sets, got:\n#{queries.join("\n")}"
  end
end

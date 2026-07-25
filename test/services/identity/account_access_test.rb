# frozen_string_literal: true

require "test_helper"

class Identity::AccountAccessTest < ActiveSupport::TestCase
  MODULE_PERMISSIONS = {
    "forum.points.manage" => "forum",
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
end

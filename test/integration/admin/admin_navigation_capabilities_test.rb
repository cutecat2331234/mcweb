# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  class AdminNavigationCapabilitiesTest < ActionDispatch::IntegrationTest
    test "shared admin navigation props expose bounded effective permissions" do
      staff = create_user(account_type: "staff")
      grant_permission(staff, "admin.access")
      grant_permission(staff, "identity.groups.read")
      grant_admin_module(staff, "identity")
      sign_in_as(staff)

      get admin_root_path

      assert_response :success
      user_props = inertia.props.deep_symbolize_keys.dig(:auth, :user)
      assert_equal [ "identity" ], user_props.fetch(:admin_modules)
      assert_includes user_props.fetch(:admin_permissions), "identity.groups.read"
      assert_not_includes user_props.fetch(:admin_permissions), "system.settings.manage"
      assert_not user_props.fetch(:admin_capabilities).fetch(:"forum.approvals.read")
    end

    test "section moderators receive the approvals capability without a global moderator grant" do
      moderator = create_user(account_type: "staff")
      grant_permission(moderator, "admin.access")
      grant_admin_module(moderator, "forum")
      category = Community::Category.create!(
        name: "Moderation",
        slug: "moderation-#{SecureRandom.hex(4)}"
      )
      section = Community::Section.create!(
        category: category,
        name: "Moderated",
        slug: "moderated-#{SecureRandom.hex(4)}",
        position: 1
      )
      Community::SectionModerator.create!(user: moderator, section: section)
      sign_in_as(moderator)

      get admin_root_path

      assert_response :success
      user_props = inertia.props.deep_symbolize_keys.dig(:auth, :user)
      assert user_props.fetch(:admin_capabilities).fetch(:"forum.approvals.read")
      assert_not_includes user_props.fetch(:admin_permissions), "forum.topics.lock"
    end
  end
end

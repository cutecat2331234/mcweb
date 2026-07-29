# frozen_string_literal: true

require "test_helper"

module Identity
  class PermissionExplanationTest < ActiveSupport::TestCase
    setup do
      @user = create_user
      @role = Role.create!(
        key: "permission_explanation_role_#{SecureRandom.hex(3)}",
        name: "Permission explanation role"
      )
      @role.grant_permission!(ensure_permission("admin.access"))
      UserRole.create!(user: @user, role: @role)
      @group = Community::UserGroup.create!(
        name: "Permission explanation group #{SecureRandom.hex(3)}",
        priority: 10,
        permissions: [ "forum.topics.lock" ]
      )
      Community::GroupMembership.create!(user: @user, user_group: @group, is_primary: true)
    end

    test "server returns final decisions with role and group source chains" do
      result = PermissionExplanation.call(user: @user, locale: :en)

      assert_predicate result, :success?, result.error
      permissions = result.value.fetch(:categories).flat_map { |category| category.fetch(:permissions) }
      admin_access = permissions.find { |permission| permission.fetch(:key) == "admin.access" }
      topic_lock = permissions.find { |permission| permission.fetch(:key) == "forum.topics.lock" }

      assert admin_access.fetch(:allowed)
      assert_equal "granted_by_role", admin_access.fetch(:reason)
      assert_equal [ "role" ], admin_access.fetch(:sources).pluck(:type)
      assert_equal @role.name, admin_access.dig(:sources, 0, :name)

      assert topic_lock.fetch(:allowed)
      assert_equal "granted_by_group", topic_lock.fetch(:reason)
      assert_equal [ "group" ], topic_lock.fetch(:sources).pluck(:type)
      assert topic_lock.dig(:sources, 0, :primary)
      assert_equal @user.reload.permission_version, result.value.dig(:user, :permission_version)
    end

    test "account eligibility overrides grants without hiding their diagnostic sources" do
      @user.update!(status: :banned, banned_at: Time.current, ban_reason: "Security review")

      result = PermissionExplanation.call(user: @user, locale: :"zh-CN")
      permission = result.value.fetch(:categories)
        .flat_map { |category| category.fetch(:permissions) }
        .find { |entry| entry.fetch(:key) == "admin.access" }

      refute permission.fetch(:allowed)
      assert_equal "account_banned", permission.fetch(:reason)
      assert_equal [ "role" ], permission.fetch(:sources).pluck(:type)
      assert_equal 0, result.value.dig(:summary, :allowed)
    end

    test "every access-affecting mutation advances the member permission version" do
      baseline = @user.reload.permission_version

      extra_permission = ensure_permission("forum.posts.edit_others")
      RolePermission.create!(role: @role, permission: extra_permission)
      after_role_permission = @user.reload.permission_version
      assert_operator after_role_permission, :>, baseline

      @group.update!(permissions: @group.permission_keys + [ "forum.posts.edit_others" ])
      after_group_permission = @user.reload.permission_version
      assert_operator after_group_permission, :>, after_role_permission

      second_role = Role.create!(
        key: "permission_version_role_#{SecureRandom.hex(3)}",
        name: "Version role"
      )
      UserRole.create!(user: @user, role: second_role)
      after_membership = @user.reload.permission_version
      assert_operator after_membership, :>, after_group_permission

      @user.update!(account_type: :staff)
      assert_operator @user.reload.permission_version, :>, after_membership
    end

    private

    def ensure_permission(key)
      Permission.find_or_create_by!(key:) do |permission|
        permission.name = key
        permission.category = key.split(".").first
      end
    end
  end
end

# frozen_string_literal: true

require "test_helper"

class UserGroupTest < ActiveSupport::TestCase
  setup do
    @user = create_user
  end

  test "membership grants the group's permission keys via User#permission?" do
    assert_not @user.permission?("forum.topics.lock")
    group = Community::UserGroup.create!(name: "Mods", priority: 10, permissions: [ "forum.topics.lock" ])
    Community::GroupMembership.create!(user: @user, user_group: group)

    # A fresh load (as each request gets) sees the group permission.
    fresh = User.find(@user.id)
    assert fresh.permission?("forum.topics.lock")
    assert_not fresh.permission?("forum.topics.delete_unrelated_key")
  end

  test "permission_keys_for unions keys across multiple groups" do
    g1 = Community::UserGroup.create!(name: "A", permissions: [ "a.one", "shared" ])
    g2 = Community::UserGroup.create!(name: "B", permissions: [ "b.two", "shared" ])
    Community::GroupMembership.create!(user: @user, user_group: g1)
    Community::GroupMembership.create!(user: @user, user_group: g2)

    keys = Community::UserGroup.permission_keys_for(@user)
    assert_equal %w[a.one b.two shared].sort, keys.sort
  end

  test "no memberships means no group permissions" do
    assert_empty Community::UserGroup.permission_keys_for(@user)
  end

  test "new registrations join the default primary group" do
    Community::UserGroup.create!(name: "Members", is_primary_default: true, permissions: [ "forum.basic" ])
    result = Identity::RegisterUser.call(
      email: "g#{SecureRandom.hex(3)}@example.com",
      username: "g#{SecureRandom.hex(3)}",
      password: "password123"
    )
    assert result.success?
    new_user = result.value[:user]
    assert new_user.permission?("forum.basic")
    assert new_user.group_memberships.primary.exists?
  end
end

# frozen_string_literal: true

require "test_helper"

module Community
  class UserProfileVisibilityTest < ActiveSupport::TestCase
    test "unsaved users are never treated as the same persisted account" do
      viewer = User.new
      subject = User.new
      unsaved_owner = User.new(account_type: :owner)

      refute UserProfileVisibility.new(user: subject, viewer: viewer).private_activity?
      refute UserProfileVisibility.new(user: viewer, viewer: viewer).private_activity?
      refute UserProfileVisibility.private_directory_visible?(viewer: unsaved_owner)
      visibility = UserProfileVisibility.new(user: subject, viewer: unsaved_owner)
      refute visibility.account_type?
      refute visibility.role_assignments?
      refute visibility.game_permission_groups?
    end

    test "the persisted account can inspect its own activity" do
      user = create_user

      assert UserProfileVisibility.new(user: user, viewer: user).private_activity?
    end
  end
end

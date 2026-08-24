# frozen_string_literal: true

require "test_helper"

module Community
  class UserProfileVisibilityTest < ActiveSupport::TestCase
    test "unsaved users are never treated as the same persisted account" do
      viewer = User.new
      subject = User.new
      subject.forum_profile_activity_public = true
      unsaved_owner = User.new(account_type: :owner)

      refute UserProfileVisibility.new(user: subject, viewer: viewer).private_activity?
      refute UserProfileVisibility.new(user: viewer, viewer: viewer).private_activity?
      refute UserProfileVisibility.new(user: subject, viewer: nil).activity_summary?
      refute UserProfileVisibility.private_directory_visible?(viewer: unsaved_owner)
      visibility = UserProfileVisibility.new(user: subject, viewer: unsaved_owner)
      refute visibility.account_type?
      refute visibility.role_assignments?
      refute visibility.game_permission_groups?
    end

    test "assigned ids do not make unsaved records trusted policy subjects or viewers" do
      persisted_subject = create_user
      assigned_subject = User.new(id: persisted_subject.id, forum_profile_activity_public: true)
      assigned_viewer = User.new(id: persisted_subject.id, account_type: :owner)

      visibility = UserProfileVisibility.new(user: assigned_subject, viewer: assigned_viewer)

      refute visibility.private_activity?
      refute visibility.activity_summary?
      refute visibility.owner?
      refute visibility.account_type?
      refute visibility.role_assignments?
      refute visibility.game_permission_groups?
      refute UserProfileVisibility.private_directory_visible?(viewer: assigned_viewer)
    end

    test "the persisted account can inspect its own activity" do
      user = create_user

      assert UserProfileVisibility.new(user: user, viewer: user).private_activity?
      assert UserProfileVisibility.new(user: user, viewer: user).activity_summary?
    end

    test "a persisted viewer needs the dedicated permission for private activity" do
      subject = create_user
      viewer = create_user(account_type: :admin)
      visibility = UserProfileVisibility.new(user: subject, viewer: viewer)

      refute visibility.private_activity?
      refute visibility.activity_summary?
      refute UserProfileVisibility.private_directory_visible?(viewer: viewer)

      grant_permission(viewer, UserProfileVisibility::PRIVATE_ACTIVITY_PERMISSION)

      assert UserProfileVisibility.new(user: subject, viewer: viewer).private_activity?
      assert UserProfileVisibility.private_directory_visible?(viewer: viewer)
    end

    test "subject opt in exposes only the activity summary and never unlocks directory sorting" do
      subject = create_user(forum_profile_activity_public: true)
      viewer = create_user
      visibility = UserProfileVisibility.new(user: subject, viewer: viewer)

      refute visibility.private_activity?
      assert visibility.activity_summary?
      assert UserProfileVisibility.new(user: subject, viewer: nil).activity_summary?
      refute UserProfileVisibility.private_directory_visible?(viewer: viewer)

      subject.update!(forum_profile_activity_public: false)

      refute UserProfileVisibility.new(user: subject, viewer: viewer).activity_summary?

      subject.update!(forum_profile_activity_public: true, status: :deleted)
      refute UserProfileVisibility.new(user: subject, viewer: nil).activity_summary?
    end
  end
end

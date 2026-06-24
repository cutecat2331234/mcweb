# frozen_string_literal: true

require "test_helper"

class FollowNotificationTest < ActiveSupport::TestCase
  test "following a user notifies the followed user" do
    follower = create_user
    followed = create_user

    assert_difference -> { followed.notifications.where(notification_type: "forum.new_follower").count }, 1 do
      result = Community::ToggleUserFollow.call(follower: follower, followed_username: followed.username)
      assert result.success?
      assert result.value[:following]
    end
  end

  test "unfollowing does not create a notification" do
    follower = create_user
    followed = create_user
    Community::UserFollow.create!(follower: follower, followed: followed)

    assert_no_difference -> { Notification.count } do
      result = Community::ToggleUserFollow.call(follower: follower, followed_username: followed.username)
      assert result.success?
      assert_not result.value[:following]
    end
  end
end

# frozen_string_literal: true

require "test_helper"

class ProfileViewCounterTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user
    @viewer = create_user
  end

  test "increments the view count when another logged-in user views the profile" do
    sign_in_as(@viewer)
    assert_difference -> { @owner.reload.forum_profile_views }, 1 do
      get forum_user_path(@owner.username)
      assert_response :success
    end
  end

  test "does not increment when viewing your own profile" do
    sign_in_as(@owner)
    assert_no_difference -> { @owner.reload.forum_profile_views } do
      get forum_user_path(@owner.username)
    end
  end
end

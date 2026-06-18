# frozen_string_literal: true

require "test_helper"

class WatchedTagsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @tag = Community::Tag.create!(name: "watch-tag-#{SecureRandom.hex(3)}", slug: "watch-tag-#{SecureRandom.hex(4)}")
    Community::Subscription.subscribe!(@user, @tag, level: "watching")
    sign_in_as(@user)
  end

  test "watched tags page lists subscribed tags" do
    get forum_watched_tags_path

    assert_response :success
    assert_includes @response.body, @tag.name
  end

  test "unsubscribe tag from watched list redirects back to watched tags" do
    patch forum_tag_subscription_level_path(@tag.slug),
          params: { level: "off" },
          headers: { "HTTP_REFERER" => forum_watched_tags_url }

    assert_redirected_to forum_watched_tags_path
    assert_not Community::Subscription.exists?(user: @user, subscribable: @tag)
  end
end

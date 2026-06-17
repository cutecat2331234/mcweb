# frozen_string_literal: true

require "test_helper"

class ForumPreferencesTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in_as(@user)
  end

  test "update preferences saves settings" do
    patch forum_preferences_path,
          params: {
            preferences: {
              "forum.topic_reply" => { in_app: false, email: false },
              "forum.mention" => { in_app: true, email: true }
            },
            digest_frequency: "daily",
            digest_watched_only: true,
            watch_email_mode: "digest_only"
          }

    assert_redirected_to forum_preferences_path
    @user.reload
    assert_equal "daily", @user.forum_digest_frequency
    assert @user.forum_digest_watched_only?
    assert_equal "digest_only", @user.forum_watch_email_mode
    assert_not NotificationPreference.enabled?(@user, channel: "in_app", notification_type: "forum.topic_reply")
  end

  test "update preferences without csrf token is rejected when forgery protection enabled" do
    @old = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    begin
      get forum_preferences_path
      assert_response :success
      token = css_select('meta[name="csrf-token"]').first&.[]("content")
      assert token.present?, "expected csrf meta tag on preferences page"

      patch forum_preferences_path,
            params: {
              preferences: { "forum.topic_reply" => { in_app: true, email: false } },
              digest_frequency: "none",
              watch_email_mode: "instant"
            },
            headers: { "X-CSRF-Token" => token }

      assert_redirected_to forum_preferences_path

      patch forum_preferences_path,
            params: {
              preferences: { "forum.topic_reply" => { in_app: true, email: false } },
              digest_frequency: "none",
              watch_email_mode: "instant"
            },
            headers: { "X-CSRF-Token" => "invalid" }

      assert_response :unprocessable_entity
    ensure
      ActionController::Base.allow_forgery_protection = @old
    end
  end
end

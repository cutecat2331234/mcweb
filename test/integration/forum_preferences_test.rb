# frozen_string_literal: true

require "test_helper"

class ForumPreferencesTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in_as(@user)
  end

  test "update preferences with csrf token" do
    get forum_preferences_path
    assert_response :success
    token = css_select('meta[name="csrf-token"]').first["content"]
    assert token.present?

    patch forum_preferences_path,
          params: {
            preferences: {
              "forum.topic_reply" => { in_app: true, email: false },
              "forum.mention" => { in_app: true, email: true }
            },
            digest_frequency: "none",
            digest_watched_only: false,
            watch_email_mode: "instant"
          },
          headers: { "X-CSRF-Token" => token }

    assert_redirected_to forum_preferences_path
    assert_equal "通知偏好已保存。", flash[:notice]
  end

  test "update preferences without csrf token is rejected when forgery protection enabled" do
    @old = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    begin
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

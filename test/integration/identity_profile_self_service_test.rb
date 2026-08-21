# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class IdentityProfileSelfServiceTest < ActionDispatch::IntegrationTest
  include InertiaRails::Minitest

  test "profile page requires a signed-in user" do
    get identity_profile_path

    assert_redirected_to identity_sign_in_path
  end

  test "profile page exposes editable and read-only identity fields without time zone" do
    user = create_user(display_name: "Display name", locale: "zh-CN")
    sign_in_as(user)

    get identity_profile_path

    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "Identity/Profiles/Show", inertia.component
    profile = inertia.props.deep_symbolize_keys.fetch(:profile)
    assert_equal user.username, profile.fetch(:username)
    assert_equal user.email, profile.fetch(:email)
    assert_equal "Display name", profile.fetch(:display_name)
    assert_equal "zh-CN", profile.fetch(:locale)
    refute profile.key?(:time_zone)
  end

  test "updating the profile synchronizes the persisted and current-session locale" do
    user = create_user(display_name: "Before", locale: "zh-CN")
    sign_in_as(user)

    patch identity_profile_path, params: {
      profile: {
        display_name: "  After  ",
        locale: "en",
        time_zone: "UTC"
      }
    }

    assert_redirected_to identity_profile_path
    assert_equal "After", user.reload.display_name
    assert_equal "en", user.locale
    assert_equal "Asia/Shanghai", user.time_zone

    follow_redirect!
    assert_response :success
    assert_equal "en", inertia.props.deep_symbolize_keys.fetch(:locale)
    assert_equal "en", inertia.props.deep_symbolize_keys.dig(:auth, :user, :locale)
  end

  test "invalid profile input returns field errors and keeps stored values" do
    user = create_user(display_name: "Before")
    sign_in_as(user)

    patch identity_profile_path, params: {
      profile: { display_name: "x" * 65, locale: "zh-CN" }
    }

    assert_response :unprocessable_entity
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "Identity/Profiles/Show", inertia.component
    errors = inertia.props.deep_symbolize_keys.fetch(:form_errors)
    assert errors.key?(:"profile.display_name")
    assert_equal "Before", user.reload.display_name
  end
end

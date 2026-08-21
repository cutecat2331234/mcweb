# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class AccountCenterTest < ActionDispatch::IntegrationTest
  test "account center requires login" do
    get account_path

    assert_redirected_to identity_sign_in_path
  end

  test "signed-in users receive a private dashboard with reusable identity and security state" do
    user = create_user(display_name: "Dashboard member", locale: "en")
    sign_in_as(user)

    get account_path

    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "Account/Show", inertia.component
    props = inertia.props.deep_symbolize_keys
    assert_equal FeatureFlags.enabled?(:forum), props.fetch(:forum_enabled)
    assert_equal FeatureFlags.enabled?(:minecraft), props.fetch(:minecraft_enabled)
    assert_equal "Dashboard member", props.dig(:identity, :display_name)
    assert_equal user.username, props.dig(:identity, :username)
    assert_equal "en", props.dig(:identity, :locale)
    assert_equal true, props.dig(:security, :email_verified)
    assert_equal false, props.dig(:security, :totp_enabled)
    assert_operator props.dig(:security, :active_sessions_count), :>=, 1

    if props.fetch(:forum_enabled)
      assert_equal %i[topic_drafts unread_messages unread_notifications],
                   props.fetch(:activity).keys.sort
    else
      assert_nil props.fetch(:activity)
    end
    if props.fetch(:minecraft_enabled)
      assert_equal false, props.dig(:minecraft, :bound)
    else
      assert_nil props.fetch(:minecraft)
    end
  end

  test "account center omits forum state when the forum feature is disabled" do
    SiteSetting.set("features.forum.enabled", "false")
    user = create_user
    sign_in_as(user)

    get account_path

    assert_response :success
    props = inertia.props.deep_symbolize_keys
    assert_equal false, props.fetch(:forum_enabled)
    assert_nil props.fetch(:activity)
  end
end

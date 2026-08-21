# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class AccountCenterTest < ActionDispatch::IntegrationTest
  test "account center requires login" do
    get account_path

    assert_redirected_to identity_sign_in_path
  end

  test "signed-in users receive the account center and feature flags" do
    user = create_user
    sign_in_as(user)

    get account_path

    assert_response :success
    assert_equal "Account/Show", inertia.component
    props = inertia.props.deep_symbolize_keys
    assert_equal FeatureFlags.enabled?(:forum), props.fetch(:forum_enabled)
    assert_equal FeatureFlags.enabled?(:minecraft), props.fetch(:minecraft_enabled)
  end

  test "account center exposes forum state when the forum feature is disabled" do
    SiteSetting.set("features.forum.enabled", "false")
    user = create_user
    sign_in_as(user)

    get account_path

    assert_response :success
    assert_equal false, inertia.props.deep_symbolize_keys.fetch(:forum_enabled)
  end
end

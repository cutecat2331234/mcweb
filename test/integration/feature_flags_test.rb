# frozen_string_literal: true

require "test_helper"

class FeatureFlagsIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(email: "feature-toggle@example.com", username: "featuretoggle")
    grant_permission(@user, "admin.access")
    grant_permission(@user, "system.settings.manage")
    sign_in_as(@user)
  end

  teardown do
    FeatureFlags.definitions.each do |definition|
      SiteSetting.set(definition.key, "true")
    end
  end

  test "admin can view and update feature toggles" do
    get admin_system_feature_toggles_path
    assert_response :success
    assert_includes response.body, "Admin/System/FeatureToggles/Show"

    patch admin_system_feature_toggles_path, params: {
      features: { forum: "0", store: "1", website_blog: "1", minecraft: "1" }
    }

    assert_redirected_to admin_system_feature_toggles_path
    assert_not FeatureFlags.enabled?(:forum)
    assert FeatureFlags.enabled?(:store)
  end

  test "admin cannot disable forum and store together" do
    patch admin_system_feature_toggles_path, params: {
      features: { forum: "0", store: "0", website_blog: "1", minecraft: "1" }
    }

    assert_redirected_to admin_system_feature_toggles_path
    assert_equal "论坛和商城至少需要保留一个开启。", flash[:alert]
    assert FeatureFlags.enabled?(:forum)
    assert FeatureFlags.enabled?(:store)
  end

  test "disabled forum redirects portal requests" do
    SiteSetting.set("features.forum.enabled", "false")

    get forum_sections_path
    assert_redirected_to store_products_path
    follow_redirect!
    assert_response :success
  end

  test "disabled store redirects portal requests" do
    SiteSetting.set("features.store.enabled", "false")

    get store_products_path
    assert_redirected_to forum_sections_path
    follow_redirect!
    assert_response :success
  end

  test "disabled blog redirects website blog" do
    SiteSetting.set("features.website_blog.enabled", "false")

    get website_articles_path
    assert_redirected_to root_path
  end

  test "disabled minecraft link redirects user page" do
    SiteSetting.set("features.minecraft.enabled", "false")

    get minecraft_link_path
    assert_redirected_to forum_sections_path
  end

  test "inertia share includes features hash" do
    SiteSetting.set("features.forum.enabled", "false")
    SiteSetting.set("features.store.enabled", "true")

    get store_products_path
    assert_response :success
    assert_includes response.body, '"features"'
    assert_includes response.body, '"forum":false'
    assert_includes response.body, '"store":true'
  end
end

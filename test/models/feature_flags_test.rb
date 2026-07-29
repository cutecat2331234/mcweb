# frozen_string_literal: true

require "test_helper"

class FeatureFlagsTest < ActiveSupport::TestCase
  setup do
    FeatureFlags.definitions.each do |definition|
      SiteSetting.where(key: definition.key).delete_all
    end
  end

  test "defaults all features to enabled" do
    FeatureFlags.definitions.each do |definition|
      assert FeatureFlags.enabled?(definition.id), "#{definition.id} should default enabled"
    end
  end

  test "update_from_params persists toggles" do
    result = FeatureFlags.update_from_params!({ "forum" => "0", "store" => "1" })
    assert result.success?

    assert_not FeatureFlags.enabled?(:forum)
    assert FeatureFlags.enabled?(:store)
  end

  test "update_from_params rejects disabling forum and store together" do
    result = FeatureFlags.update_from_params!({ "forum" => "0", "store" => "0" })

    assert result.failure?
    assert_includes result.error, "论坛和商城"
    assert FeatureFlags.enabled?(:forum)
    assert FeatureFlags.enabled?(:store)
  end

  test "feature_for_path maps request prefixes" do
    assert_equal :forum, FeatureFlags.feature_for_path("/app/forum/sections")
    assert_equal :store, FeatureFlags.feature_for_path("/app/store/products")
    assert_equal :website_blog, FeatureFlags.feature_for_path("/blog/sample-post")
    assert_equal :minecraft, FeatureFlags.feature_for_path("/app/minecraft/link")
    assert_nil FeatureFlags.feature_for_path("/admin/users")
  end

  test "disabled messages localize known and unknown features" do
    I18n.with_locale(:en) do
      assert_equal(
        "Forum has been disabled by an administrator.",
        FeatureFlags.disabled_message(:forum)
      )
      assert_equal(
        "This feature has been disabled by an administrator.",
        FeatureFlags.disabled_message(:unknown)
      )
    end

    I18n.with_locale(:"zh-CN") do
      assert_equal "论坛已被管理员关闭。", FeatureFlags.disabled_message(:forum)
      assert_equal "该功能已被管理员关闭。", FeatureFlags.disabled_message(:unknown)
    end
  end
end

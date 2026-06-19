# frozen_string_literal: true

require "test_helper"

class Round73AdminForumSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
    @previous = SiteSetting.get("forum.group_pm_creator_only_add")
  end

  teardown do
    SiteSetting.set("forum.group_pm_creator_only_add", @previous || "false")
  end

  test "forum settings page renders" do
    sign_in_as(@admin)
    get admin_forum_settings_path
    assert_response :success
    assert_includes response.body, "forum.group_pm_creator_only_add"
    assert_includes response.body, "仅群主可添加群成员"
  end

  test "forum settings update group_pm_creator_only_add" do
    sign_in_as(@admin)
    patch admin_forum_settings_path, params: {
      settings: { "forum.group_pm_creator_only_add" => "true" }
    }
    assert_redirected_to admin_forum_settings_path
    assert_equal "true", SiteSetting.get("forum.group_pm_creator_only_add")
  end
end

class Round73SavedSearchUpdateTest < ActionDispatch::IntegrationTest
  test "patch saved search toggles notify_daily" do
    user = create_user
    search = user.forum_saved_searches.create!(name: "Alerts", query: "bug", notify_daily: false, filters: {})
    sign_in_as(user)

    patch forum_saved_search_path(search), params: {
      saved_search: { notify_daily: true }
    }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert body["notify_daily"]
    assert search.reload.notify_daily?
  end
end

class Round73PreferencesSavedSearchesTest < ActionDispatch::IntegrationTest
  test "preferences page lists saved searches with notify" do
    user = create_user
    user.forum_saved_searches.create!(name: "Daily", query: "release", notify_daily: true, filters: {})
    sign_in_as(user)

    get forum_preferences_path
    assert_response :success
    assert_includes response.body, "savedSearches"
    assert_includes response.body, "Daily"
    assert_includes response.body, '"notify_daily":true'
  end
end

class Round73CategoryPriceFilterTest < ActionDispatch::IntegrationTest
  test "category page supports price filters and chips" do
    user = create_user
    category = Commerce::Category.create!(
      name: "R73 Cat",
      slug: "r73-cat-#{SecureRandom.hex(4)}",
      position: 0
    )
    cheap = Commerce::Product.create!(
      name: "Cheap R73",
      slug: "r73-cheap-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 500,
      currency: "CNY",
      minimum_quantity: 1,
      stock: 5,
      category: category,
      public_id: "pub_r73ch_#{SecureRandom.hex(4)}"
    )
    Commerce::Product.create!(
      name: "Expensive R73",
      slug: "r73-exp-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 50000,
      currency: "CNY",
      minimum_quantity: 1,
      stock: 5,
      category: category,
      public_id: "pub_r73ex_#{SecureRandom.hex(4)}"
    )

    sign_in_as(user)
    get store_category_path(category.slug), params: { price_min: "1", price_max: "20" }
    assert_response :success
    assert_includes response.body, cheap.name
    assert_includes response.body, "priceMin"
    assert_includes response.body, '"priceMax":"20"'
  end
end

class Round73CategoryFilterChipsUiTest < ActionDispatch::IntegrationTest
  test "category show vue has filter chips and price inputs" do
    content = File.read(Rails.root.join("app/javascript/pages/Commerce/Categories/Show.vue"))
    assert_includes content, "hasActiveFilters"
    assert_includes content, "priceMin"
    assert_includes content, "clearFilters"
    assert_includes content, "commerce.productList.activeFilters"
  end
end

class Round73PreferencesSavedSearchUiTest < ActionDispatch::IntegrationTest
  test "preferences vue has saved search notify toggle" do
    content = File.read(Rails.root.join("app/javascript/pages/Community/Preferences/Show.vue"))
    assert_includes content, "toggleSavedSearchNotify"
    assert_includes content, "savedSearches"
  end
end

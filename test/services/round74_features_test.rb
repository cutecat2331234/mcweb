# frozen_string_literal: true

require "test_helper"

class Round74AdminStoreSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
  end

  test "store settings page renders" do
    sign_in_as(@admin)
    get admin_store_settings_path
    assert_response :success
    assert_includes response.body, "store.compare_max_items"
    assert_includes response.body, "对比列表上限"
  end

  test "store settings update compare max" do
    previous = SiteSetting.get("store.compare_max_items")
    sign_in_as(@admin)
    patch admin_store_settings_path, params: {
      settings: { "store.compare_max_items" => "6" }
    }
    assert_redirected_to admin_store_settings_path
    assert_equal "6", SiteSetting.get("store.compare_max_items")
  ensure
    SiteSetting.set("store.compare_max_items", previous || "4")
  end
end

class Round74SearchSavedNotifyToggleTest < ActionDispatch::IntegrationTest
  test "search page exposes update_url on saved searches" do
    user = create_user
    user.forum_saved_searches.create!(name: "Toggle", query: "test", notify_daily: false, filters: {})
    sign_in_as(user)

    get forum_search_path
    assert_response :success
    assert_includes response.body, "update_url"
    assert_includes response.body, "Toggle"
  end

  test "search vue has toggle notify on saved chips" do
    content = File.read(Rails.root.join("app/javascript/pages/Community/Search/Index.vue"))
    assert_includes content, "toggleSavedSearchNotify"
    assert_includes content, "togglingNotifyId"
  end
end

class Round74PreferencesDeleteSavedSearchTest < ActionDispatch::IntegrationTest
  test "preferences exposes delete_url for saved searches" do
    user = create_user
    search = user.forum_saved_searches.create!(name: "Del", query: "x", filters: {})
    sign_in_as(user)

    get forum_preferences_path
    assert_response :success
    assert_includes response.body, "delete_url"
    assert_includes response.body, "/forum/saved_searches/#{search.id}"
  end

  test "preferences vue has delete saved search" do
    content = File.read(Rails.root.join("app/javascript/pages/Community/Preferences/Show.vue"))
    assert_includes content, "deleteSavedSearch"
    assert_includes content, "delete_url"
  end
end

class Round74CategorySortRatingDiscountTest < ActionDispatch::IntegrationTest
  test "category supports rating and discount_desc sort" do
    user = create_user
    category = Commerce::Category.create!(
      name: "R74 Sort",
      slug: "r74-sort-#{SecureRandom.hex(4)}",
      position: 0
    )
    on_sale = Commerce::Product.create!(
      name: "Sale R74",
      slug: "r74-sale-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 500,
      compare_at_price_cents: 2000,
      currency: "CNY",
      minimum_quantity: 1,
      stock: 5,
      category: category,
      public_id: "pub_r74sl_#{SecureRandom.hex(4)}"
    )

    sign_in_as(user)
    get store_category_path(category.slug), params: { sort: "discount_desc" }
    assert_response :success
    assert_includes response.body, on_sale.name

    get store_category_path(category.slug), params: { sort: "rating" }
    assert_response :success
  end

  test "category vue includes rating and discount sort options" do
    content = File.read(Rails.root.join("app/javascript/pages/Commerce/Categories/Show.vue"))
    assert_includes content, "discount_desc"
    assert_includes content, "rating"
  end
end

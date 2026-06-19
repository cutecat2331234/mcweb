# frozen_string_literal: true

require "test_helper"

class Round76SavedSearchLimitTest < ActionDispatch::IntegrationTest
  setup do
    @previous = SiteSetting.get("forum.saved_search_limit")
    SiteSetting.set("forum.saved_search_limit", "2")
  end

  teardown do
    SiteSetting.set("forum.saved_search_limit", @previous || "20")
  end

  test "cannot create saved search beyond limit" do
    user = create_user
    user.forum_saved_searches.create!(name: "One", query: "a", filters: {})
    user.forum_saved_searches.create!(name: "Two", query: "b", filters: {})
    sign_in_as(user)

    post forum_saved_searches_path, params: {
      saved_search: { name: "Three", query: "c", filters: {} }
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal 2, user.forum_saved_searches.count
  end

  test "search page exposes saved search limit and count" do
    user = create_user
    user.forum_saved_searches.create!(name: "One", query: "a", filters: {})
    sign_in_as(user)

    get forum_search_path
    assert_response :success
    assert_includes response.body, "savedSearchLimit"
    assert_includes response.body, "savedSearchCount"
  end
end

class Round76SavedSearchUnsubscribeTest < ActionDispatch::IntegrationTest
  test "unsubscribe token disables notify daily" do
    user = create_user
    search = user.forum_saved_searches.create!(name: "Unsub", query: "x", notify_daily: true, filters: {})
    token = Community::SavedSearchUnsubscribeToken.generate(search)

    get unsubscribe_forum_saved_searches_path(token: token)
    assert_redirected_to forum_preferences_path
    assert_not search.reload.notify_daily?
  end

  test "invalid unsubscribe token redirects with alert" do
    get unsubscribe_forum_saved_searches_path(token: "invalid")
    assert_redirected_to forum_search_path
    assert_match(/无效|过期/, flash[:alert].to_s)
  end

  test "digest email includes unsubscribe url" do
    content = File.read(Rails.root.join("app/views/community/forum_mailer/saved_search_digest.html.erb"))
    assert_includes content, "@unsubscribe_url"
    assert_includes content, "unsubscribe_search"
  end
end

class Round76PreferencesRenameSavedSearchTest < ActionDispatch::IntegrationTest
  test "preferences vue supports rename saved search" do
    content = File.read(Rails.root.join("app/javascript/pages/Community/Preferences/Show.vue"))
    assert_includes content, "saveRenameSearch"
    assert_includes content, "startRenameSearch"
  end
end

class Round76StoreShippingVisualFormTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
    @previous = SiteSetting.get("store.shipping_methods")
  end

  teardown do
    SiteSetting.set("store.shipping_methods", @previous) if @previous
  end

  test "store settings page exposes shipping methods visual editor" do
    sign_in_as(@admin)
    get admin_store_settings_path
    assert_response :success
    assert_includes response.body, "shippingMethods"
    content = File.read(Rails.root.join("app/javascript/pages/Admin/Store/Settings/Show.vue"))
    assert_includes content, "addShippingMethod"
  end

  test "store settings update shipping methods from array" do
    sign_in_as(@admin)
    patch admin_store_settings_path, params: {
      settings: {},
      shipping_methods: [
        { code: "pickup", label: "自提", cents: 0, delivery_days_min: 0, delivery_days_max: 0 }
      ]
    }
    assert_redirected_to admin_store_settings_path
    methods = JSON.parse(SiteSetting.get("store.shipping_methods"))
    assert_equal "pickup", methods.first["code"]
  end
end

class Round76ForumSettingsSavedSearchLimitTest < ActionDispatch::IntegrationTest
  test "forum settings includes saved search limit" do
    content = File.read(Rails.root.join("app/controllers/admin/forum/settings_controller.rb"))
    assert_includes content, "forum.saved_search_limit"
  end
end

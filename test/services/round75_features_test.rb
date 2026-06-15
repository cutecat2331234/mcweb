# frozen_string_literal: true

require "test_helper"

class Round75SavedSearchRenameTest < ActionDispatch::IntegrationTest
  test "patch saved search renames" do
    user = create_user
    search = user.forum_saved_searches.create!(name: "Old", query: "x", filters: {})
    sign_in_as(user)

    patch forum_saved_search_path(search), params: {
      saved_search: { name: "Renamed R75" }
    }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Renamed R75", body["name"]
    assert_equal "Renamed R75", search.reload.name
  end

  test "search vue supports inline rename" do
    content = File.read(Rails.root.join("app/javascript/pages/Community/Search/Index.vue"))
    assert_includes content, "saveRenameSearch"
    assert_includes content, "startRenameSearch"
  end
end

class Round75SavedSearchDigestEmailTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "digest email template includes preferences link" do
    content = File.read(Rails.root.join("app/views/community/forum_mailer/saved_search_digest.html.erb"))
    assert_includes content, "@preferences_url"
    assert_includes content, "通知偏好"
  end

  test "mailer sets preferences url" do
    user = create_user
    search = user.forum_saved_searches.create!(name: "Mail", query: "q", notify_daily: true, filters: {})
    topic = create_forum_topic_for_digest(user)

    mail = Community::ForumMailer.saved_search_digest(search.id, [ topic.id ])
    assert_includes mail.body.encoded, "preferences"
  end

  private

  def create_forum_topic_for_digest(user)
    suffix = SecureRandom.hex(4)
    category = Community::Category.find_or_create_by!(slug: "r75-#{suffix}") { |c| c.name = "R75" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r75-sec-#{suffix}") { |s| s.name = "S"; s.position = 0 }
    Community::CreateTopic.call(
      user: user,
      section: section,
      title: "DigestTopic#{suffix}",
      body: "OP",
      ip_address: "127.0.0.1"
    ).value
  end
end

class Round75StoreShippingMethodsSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
    @previous = SiteSetting.get("store.shipping_methods")
  end

  teardown do
    SiteSetting.set("store.shipping_methods", @previous) if @previous
  end

  test "store settings page includes shipping methods" do
    sign_in_as(@admin)
    get admin_store_settings_path
    assert_response :success
    assert_includes response.body, "shippingMethods"
    assert_includes response.body, "标准配送"
  end

  test "store settings rejects empty shipping methods" do
    sign_in_as(@admin)
    patch admin_store_settings_path, params: {
      settings: {},
      shipping_methods: []
    }
    assert_redirected_to admin_store_settings_path
    assert_match(/失败/, flash[:alert].to_s)
  end

  test "store settings accepts valid shipping array" do
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

class Round75CategoryNewestSortTest < ActionDispatch::IntegrationTest
  test "category defaults sort to newest" do
    user = create_user
    category = Commerce::Category.create!(
      name: "R75 Newest",
      slug: "r75-new-#{SecureRandom.hex(4)}",
      position: 0
    )
    sign_in_as(user)
    get store_category_path(category.slug)
    assert_response :success
    assert_includes response.body, '"sort":"newest"'
  end

  test "category vue uses newest sort option" do
    content = File.read(Rails.root.join("app/javascript/pages/Commerce/Categories/Show.vue"))
    assert_includes content, 'value="newest"'
    assert_includes content, "newest: '最新'"
  end
end

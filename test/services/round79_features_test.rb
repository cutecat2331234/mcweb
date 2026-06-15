# frozen_string_literal: true

require "test_helper"

class Round79SavedSearchWebhookDeliveryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create_user
    @search = @user.forum_saved_searches.create!(
      name: "Hook Log",
      query: "x",
      webhook_url: "https://example.com/hook",
      filters: {}
    )
  end

  test "webhook job creates delivery record" do
    payload = { "event" => "saved_search.match", "search_id" => @search.id }

    assert_difference -> { Community::SavedSearchWebhookDelivery.count }, 1 do
      Community::DispatchSavedSearchWebhookJob.perform_now(@search.id, "http://127.0.0.1:1/invalid", payload)
    end

    delivery = Community::SavedSearchWebhookDelivery.last
    assert_equal "failed", delivery.status
    assert_equal @search.id, delivery.saved_search_id
    assert delivery.response_body.present?
  end
end

class Round79WatchingOpmlTest < ActionDispatch::IntegrationTest
  test "watching opml includes subscribed tag rss" do
    user = create_user
    tag = Community::Tag.create!(name: "R79Tag", slug: "r79-tag-#{SecureRandom.hex(4)}")
    Community::Subscription.create!(user: user, subscribable: tag)
    token = Community::WatchingOpmlToken.generate(user)

    get forum_watching_opml_path(token: token)
    assert_response :success
    assert_includes response.body, "<opml"
    assert_includes response.body, tag.name
    assert_includes response.body, "type=\"rss\""
  end

  test "preferences exposes watching opml url" do
    user = create_user
    sign_in_as(user)
    get forum_preferences_path
    assert_response :success
    assert_includes response.body, "watchingOpmlUrl"
  end
end

class Round79SearchSuggestEnhancementsTest < ActionDispatch::IntegrationTest
  test "suggest includes sections and saved searches when logged in" do
    user = create_user
    category = Community::Category.find_or_create_by!(slug: "r79-suggest") { |c| c.name = "Suggest Cat" }
    Community::Section.find_or_create_by!(category: category, slug: "r79-suggest-sec") do |s|
      s.name = "SuggestSection"
      s.position = 0
    end
    user.forum_saved_searches.create!(name: "SuggestQuery", query: "q", filters: {})
    sign_in_as(user)

    get forum_search_suggest_path, params: { q: "Suggest" }
    assert_response :success
    body = response.parsed_body
    assert body["sections"].any? { |s| s["name"].include?("Suggest") }
    assert body["saved_searches"].any? { |s| s["name"] == "SuggestQuery" }
  end

  test "search vue supports section and saved search suggestions" do
    content = File.read(Rails.root.join("app/javascript/pages/Community/Search/Index.vue"))
    assert_includes content, "suggestSections"
    assert_includes content, "suggestSavedSearches"
  end
end

class Round79OrderShippedTrackingUrlTest < ActiveSupport::TestCase
  test "tracking url helper used by mailer" do
    order = Commerce::Order.new(tracking_number: "TN999", shipping_carrier: "sf")
    url = Commerce::TrackingUrl.for_order(order)
    assert_includes url, "TN999"
  end

  test "order shipped email includes tracking link" do
    content = File.read(Rails.root.join("app/views/commerce/order_mailer/order_shipped.html.erb"))
    assert_includes content, "@tracking_url"
    assert_includes content, "查询物流"
  end
end

class Round79PreferencesWebhookDeliveriesTest < ActionDispatch::IntegrationTest
  test "preferences exposes webhook delivery log" do
    user = create_user
    search = user.forum_saved_searches.create!(name: "D", query: "x", webhook_url: "https://example.com/h", filters: {})
    Community::SavedSearchWebhookDelivery.create!(
      saved_search: search,
      event_type: "saved_search.match",
      url: "https://example.com/h",
      status: "success",
      response_code: 200
    )
    sign_in_as(user)

    get forum_preferences_path
    assert_response :success
    assert_includes response.body, "savedSearchWebhookDeliveries"
    assert_includes response.body, "success"
  end
end

class Round79TrackingUrlRefactorTest < ActiveSupport::TestCase
  test "inertia uses tracking url module" do
    content = File.read(Rails.root.join("app/controllers/concerns/inertia_serializable.rb"))
    assert_includes content, "Commerce::TrackingUrl.for_order"
  end
end

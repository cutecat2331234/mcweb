# frozen_string_literal: true

require "test_helper"

class Round81TitleOnlySearchTest < ActionDispatch::IntegrationTest
  setup do
    @section = Community::Section.first || Community::Section.create!(
      name: "R81 Section",
      slug: "r81-sec-#{SecureRandom.hex(4)}",
      category: Community::Category.find_or_create_by!(slug: "r81-cat") { |c| c.name = "R81 Cat" },
      position: 0
    )
    @user = create_user
    @topic = Community::Topic.create!(
      title: "UniqueTitleR81Keyword",
      section: @section,
      user: @user,
      status: :published
    )
    Community::Post.create!(
      topic: @topic,
      user: @user,
      body: "UniqueBodyR81Keyword not in title",
      floor_number: 1,
      status: :published
    )
  end

  test "title only search returns topics but not matching posts" do
    get forum_search_path, params: { q: "UniqueTitleR81Keyword", title_only: "1" }
    assert_response :success
    assert_includes response.body, "UniqueTitleR81Keyword"
    assert_includes response.body, '"posts":[]'
    assert_includes response.body, '"count":0'
  end

  test "search page supports title only filter" do
    content = File.read(Rails.root.join("app/javascript/pages/Community/Search/Index.vue"))
    assert_includes content, "titleOnly"
    assert_includes content, "forum.search.titleOnly"
  end

  test "parse search query supports in:title" do
    result = Community::ParseSearchQuery.call(query: "hello in:title")
    assert result.success?
    assert_equal "hello", result.value[:query]
    assert result.value[:title_only_filter]
  end
end

class Round81WebhookAutoRetryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create_user
    @search = @user.forum_saved_searches.create!(
      name: "Auto Retry",
      query: "x",
      webhook_url: "https://example.com/hook",
      filters: {}
    )
  end

  test "failed webhook job schedules retry with delivery id" do
    payload = { "event" => "saved_search.match", "search_id" => @search.id }

    assert_enqueued_jobs 1, only: Community::DispatchSavedSearchWebhookJob do
      Community::DispatchSavedSearchWebhookJob.perform_now(@search.id, "http://127.0.0.1:1/invalid", payload)
    end

    delivery = Community::SavedSearchWebhookDelivery.last
    assert_equal "failed", delivery.status
    assert_equal 1, delivery.attempt_count
  end

  test "stale pending job requeues delivery" do
    delivery = Community::SavedSearchWebhookDelivery.create!(
      saved_search: @search,
      event_type: "saved_search.match",
      url: "https://example.com/h",
      status: "pending",
      request_payload: { "event" => "saved_search.match" },
      attempt_count: 1,
      created_at: 10.minutes.ago,
      updated_at: 10.minutes.ago
    )

    assert_enqueued_with(job: Community::DispatchSavedSearchWebhookJob) do
      Community::RetryFailedSavedSearchWebhooksJob.perform_now
    end

    delivery.reload
    assert_equal 2, delivery.attempt_count
  end
end

class Round81AdminWebhookDeliveryShowTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
    @user = create_user
    @search = @user.forum_saved_searches.create!(name: "Show Hook", query: "x", filters: {})
    @delivery = Community::SavedSearchWebhookDelivery.create!(
      saved_search: @search,
      event_type: "saved_search.match",
      url: "https://example.com/h",
      status: "failed",
      response_code: 500,
      response_body: "error body",
      request_payload: { "event" => "saved_search.match" },
      attempt_count: 2
    )
  end

  test "admin webhook delivery show includes payload sections" do
    sign_in_as(@admin)
    get admin_forum_webhook_delivery_path(@delivery)
    assert_response :success
    assert_includes response.body, "preformattedSections"
    assert_includes response.body, "请求体"
    assert_includes response.body, "error body"
  end

  test "admin webhook index rows link to show" do
    sign_in_as(@admin)
    get admin_forum_webhook_deliveries_path
    assert_response :success
    assert_includes response.body, admin_forum_webhook_delivery_path(@delivery)
    assert_includes response.body, "statusTabs"
  end

  test "admin retry uses admin retry service" do
    sign_in_as(@admin)
    assert_enqueued_with(job: Community::DispatchSavedSearchWebhookJob) do
      post retry_admin_forum_webhook_delivery_path(@delivery)
    end
    assert_redirected_to admin_forum_webhook_delivery_path(@delivery)
  end
end

class Round81StoreWebhookAdminIndexTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
    Commerce::OrderWebhookDelivery.create!(
      event_type: "order.paid",
      order_public_id: "ord_r81",
      url: "https://example.com/hook",
      status: "success",
      response_code: 200,
      request_payload: { "event" => "order.paid" },
      attempt_count: 1
    )
  end

  test "admin store webhook deliveries index" do
    sign_in_as(@admin)
    get admin_store_webhook_deliveries_path
    assert_response :success
    assert_includes response.body, "ord_r81"
    assert_includes response.body, "order.paid"
  end

  test "order webhook job stores request payload" do
    payload = { "event" => "order.paid", "order_id" => "ord_x" }
    Commerce::DispatchOrderWebhookJob.perform_now("http://127.0.0.1:1/invalid", payload)

    delivery = Commerce::OrderWebhookDelivery.last
    assert_equal payload.stringify_keys, delivery.request_payload
  end
end

class Round81RetryGuardTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = create_user
    @search = @user.forum_saved_searches.create!(name: "Guard", query: "x", filters: {})
    @delivery = Community::SavedSearchWebhookDelivery.create!(
      saved_search: @search,
      event_type: "saved_search.match",
      url: "https://example.com/h",
      status: "success",
      request_payload: { "event" => "saved_search.match" }
    )
  end

  test "user retry rejects non failed delivery" do
    sign_in_as(@user)
    post forum_retry_saved_search_webhook_delivery_path(@delivery)
    assert_redirected_to forum_preferences_path
    assert_no_enqueued_jobs only: Community::DispatchSavedSearchWebhookJob
  end
end

class Round81ShippingTimelineFulfilledTest < ActiveSupport::TestCase
  test "fulfilled order marks in transit done" do
    user = create_user
    order = Commerce::Order.create!(
      public_id: "ord_r81f_#{SecureRandom.hex(4)}",
      order_number: "R81F#{SecureRandom.hex(3).upcase}",
      user: user,
      status: "fulfilled",
      subtotal_cents: 1000,
      total_cents: 1800,
      shipping_method: "standard",
      shipped_at: 2.hours.ago
    )
    Commerce::OrderItem.create!(
      order: order,
      product_name: "Physical",
      unit_price_cents: 1000,
      quantity: 1,
      total_cents: 1000,
      fulfillment_snapshot: { "product_type" => "physical" }
    )

    steps = Commerce::OrderShippingTimeline.call(order)
    in_transit = steps.find { |s| s[:key] == "in_transit" }
    delivered = steps.find { |s| s[:key] == "delivered" }
    assert_equal "done", in_transit[:state]
    assert_equal "done", delivered[:state]
  end
end

class Round81AdminNavStoreWebhooksTest < ActiveSupport::TestCase
  test "admin layout links to store webhook deliveries" do
    content = File.read(Rails.root.join("app/javascript/layouts/AdminLayout.vue"))
    assert_includes content, "storeWebhookDeliveries"
  end
end

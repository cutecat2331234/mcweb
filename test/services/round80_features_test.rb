# frozen_string_literal: true

require "test_helper"

class Round80WebhookPayloadTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create_user
    @search = @user.forum_saved_searches.create!(
      name: "Payload Hook",
      query: "x",
      webhook_url: "https://example.com/hook",
      filters: {}
    )
  end

  test "webhook job stores request payload on delivery" do
    payload = { "event" => "saved_search.match", "search_id" => @search.id }

    Community::DispatchSavedSearchWebhookJob.perform_now(@search.id, "http://127.0.0.1:1/invalid", payload)

    delivery = Community::SavedSearchWebhookDelivery.last
    assert_equal payload.stringify_keys, delivery.request_payload
  end
end

class Round80RetrySavedSearchWebhookTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create_user
    @other = create_user
    @search = @user.forum_saved_searches.create!(
      name: "Retry Hook",
      query: "x",
      webhook_url: "https://example.com/hook",
      filters: {}
    )
    @delivery = Community::SavedSearchWebhookDelivery.create!(
      saved_search: @search,
      event_type: "saved_search.match",
      url: "https://example.com/hook",
      status: "failed",
      request_payload: { "event" => "saved_search.match", "search_id" => @search.id }
    )
  end

  test "retry queues job for owner" do
    assert_enqueued_with(job: Community::DispatchSavedSearchWebhookJob) do
      result = Community::RetrySavedSearchWebhook.call(delivery: @delivery, actor: @user)
      assert result.success?
    end
  end

  test "retry rejects other user" do
    result = Community::RetrySavedSearchWebhook.call(delivery: @delivery, actor: @other)
    assert_not result.success?
    assert_equal "无权操作", result.error
  end

  test "retry rejects missing payload" do
    @delivery.update!(request_payload: {})
    result = Community::RetrySavedSearchWebhook.call(delivery: @delivery, actor: @user)
    assert_not result.success?
    assert_equal "缺少请求内容，无法重试", result.error
  end
end

class Round80WebhookRetryControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = create_user
    @search = @user.forum_saved_searches.create!(
      name: "Retry UI",
      query: "x",
      webhook_url: "https://example.com/hook",
      filters: {}
    )
    @delivery = Community::SavedSearchWebhookDelivery.create!(
      saved_search: @search,
      event_type: "saved_search.match",
      url: "https://example.com/hook",
      status: "failed",
      request_payload: { "event" => "saved_search.match" }
    )
  end

  test "preferences exposes retry url for failed delivery with payload" do
    sign_in_as(@user)
    get forum_preferences_path
    assert_response :success
    assert_includes response.body, "retry_url"
    assert_includes response.body, forum_retry_saved_search_webhook_delivery_path(@delivery)
  end

  test "retry action queues webhook and redirects" do
    sign_in_as(@user)

    assert_enqueued_with(job: Community::DispatchSavedSearchWebhookJob) do
      post forum_retry_saved_search_webhook_delivery_path(@delivery)
    end
    assert_redirected_to forum_preferences_path
  end
end

class Round80AdminWebhookDeliveriesTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
    @user = create_user
    @search = @user.forum_saved_searches.create!(name: "Admin Log", query: "x", filters: {})
    @delivery = Community::SavedSearchWebhookDelivery.create!(
      saved_search: @search,
      event_type: "saved_search.match",
      url: "https://example.com/h",
      status: "success",
      response_code: 200
    )
  end

  test "admin webhook deliveries index lists records" do
    sign_in_as(@admin)
    get admin_forum_webhook_deliveries_path
    assert_response :success
    assert_includes response.body, "Admin Log"
    assert_includes response.body, "success"
  end

  test "admin webhook deliveries filters by status" do
    sign_in_as(@admin)
    get admin_forum_webhook_deliveries_path, params: { status: "failed" }
    assert_response :success
    assert_not_includes response.body, "Admin Log"
  end
end

class Round80OrderShippingTimelineTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_r80_#{SecureRandom.hex(4)}",
      order_number: "R80#{SecureRandom.hex(3).upcase}",
      user: @user,
      status: "paid",
      subtotal_cents: 1000,
      shipping_cents: 800,
      total_cents: 1800,
      shipping_method: "standard"
    )
    Commerce::OrderItem.create!(
      order: @order,
      product_name: "Physical item",
      unit_price_cents: 1000,
      quantity: 1,
      total_cents: 1000,
      fulfillment_snapshot: { "product_type" => "physical" }
    )
  end

  test "timeline shows placed and paid for physical order" do
    steps = Commerce::OrderShippingTimeline.call(@order)
    assert steps.any?
    placed = steps.find { |s| s[:key] == "placed" }
    paid = steps.find { |s| s[:key] == "paid" }
    assert_equal "done", placed[:state]
    assert_equal "done", paid[:state]
  end

  test "timeline marks shipped and in transit when tracking present" do
    @order.update!(status: "processing", shipped_at: 1.hour.ago, tracking_number: "SF123")
    steps = Commerce::OrderShippingTimeline.call(@order)
    shipped = steps.find { |s| s[:key] == "shipped" }
    in_transit = steps.find { |s| s[:key] == "in_transit" }
    delivered = steps.find { |s| s[:key] == "delivered" }
    assert_equal "done", shipped[:state]
    assert_equal "done", in_transit[:state]
    assert_equal "current", delivered[:state]
  end

  test "timeline empty for virtual only order" do
    @order.items.update_all(fulfillment_snapshot: { product_type: "virtual" })
    assert_empty Commerce::OrderShippingTimeline.call(@order.reload)
  end
end

class Round80OrderShowShippingTimelineTest < ActionDispatch::IntegrationTest
  test "order show includes shipping timeline props" do
    user = create_user
    order = Commerce::Order.create!(
      public_id: "ord_r80s_#{SecureRandom.hex(4)}",
      order_number: "R80S#{SecureRandom.hex(3).upcase}",
      user: user,
      status: "paid",
      subtotal_cents: 1000,
      total_cents: 1800,
      shipping_method: "standard"
    )
    Commerce::OrderItem.create!(
      order: order,
      product_name: "Physical item",
      unit_price_cents: 1000,
      quantity: 1,
      total_cents: 1000,
      fulfillment_snapshot: { "product_type" => "physical" }
    )

    sign_in_as(user)
    get store_order_path(order)
    assert_response :success
    assert_includes response.body, "shipping_timeline"
  end
end

class Round80LiveSearchTest < ActiveSupport::TestCase
  test "search page supports debounced live search" do
    content = File.read(Rails.root.join("app/javascript/pages/Community/Search/Index.vue"))
    assert_includes content, "liveSearch"
    assert_includes content, "450"
    assert_includes content, "preserveScroll"
  end
end

class Round80AdminNavWebhookDeliveriesTest < ActiveSupport::TestCase
  test "admin layout links to forum webhook deliveries" do
    content = File.read(Rails.root.join("app/javascript/layouts/AdminLayout.vue"))
    assert_includes content, "forumWebhookDeliveries"
    assert_includes content, "admin.forumWebhookDeliveries"
  end
end

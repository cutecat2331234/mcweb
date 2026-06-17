# frozen_string_literal: true

require "test_helper"

class Round98NotificationDestinationUrlTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @notification = Notification.create!(
      user: @user,
      notification_type: "forum.topic_reply",
      title: "Reply",
      body: "body",
      metadata: { path: "/forum/topics/abc123" }
    )
  end

  test "builds absolute url from metadata path" do
    url = Community::NotificationDestinationUrl.for(@notification, root_url: "https://example.com")
    assert_equal "https://example.com/app/forum/topics/abc123", url
  end

  test "notification destination_path normalizes legacy forum paths" do
    assert_equal "/app/forum/topics/abc123", @notification.destination_path
  end
end

class Round98DigestLinksTest < ActionMailer::TestCase
  setup do
    @user = create_user
    @notification = Notification.create!(
      user: @user,
      notification_type: "forum.reaction",
      title: "Reaction",
      body: "Someone reacted",
      metadata: { path: "/forum/topics/topic1" }
    )
  end

  test "digest email includes notification link" do
    email = Community::ForumMailer.digest(@user.id, [ @notification.id ])
    assert_includes email.html_part.body.decoded, "/app/forum/topics/topic1"
  end
end

class Round98NotificationVisitTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @notification = Notification.create!(
      user: @user,
      notification_type: "forum.topic_reply",
      title: "Reply",
      body: "body",
      metadata: { path: "/forum/topics/legacy1" }
    )
    sign_in_as(@user)
  end

  test "visit redirects legacy notification paths to app scope" do
    get visit_forum_notification_path(@notification)
    assert_redirected_to "/app/forum/topics/legacy1"
  end
end

class Round98StoreOrdersTabsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    Commerce::Order.create!(
      public_id: "ord_r98_#{SecureRandom.hex(8)}",
      order_number: "PAID#{SecureRandom.hex(4)}",
      user: @user,
      status: "paid",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY"
    )
    sign_in_as(@user)
  end

  test "orders index includes status tabs and active filters" do
    get store_orders_path(status: "paid", q: "PAID")
    assert_response :success
    assert_includes response.body, "statusTabs"
    assert_includes response.body, "activeFilters"
  end

  test "export respects status filter" do
    Commerce::Order.create!(
      public_id: "ord_r98p_#{SecureRandom.hex(8)}",
      order_number: "PEND#{SecureRandom.hex(4)}",
      user: @user,
      status: "pending",
      subtotal_cents: 500,
      total_cents: 500,
      currency: "CNY"
    )
    get export_store_orders_path(format: :csv, status: "paid")
    assert_response :success
    assert_includes response.body, "PAID"
    refute_includes response.body, "PEND"
  end
end

class Round98WebhookEventTabsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
    Commerce::OrderWebhookDelivery.create!(
      order_public_id: "ord_r98",
      event_type: "order.paid",
      status: "success",
      url: "https://example.com/hook",
      request_payload: {},
      response_code: 200
    )
    sign_in_as(@admin)
  end

  test "webhook event tabs include counts" do
    get admin_store_webhook_deliveries_path
    assert_response :success
    assert_includes response.body, "eventTabs"
    assert_includes response.body, "order.paid"
    assert_includes response.body, '"count"'
  end
end

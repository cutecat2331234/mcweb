# frozen_string_literal: true

require "test_helper"

class Community::ArchivedTopicFilterTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r52-arch") { |c| c.name = "A" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r52-arch-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @user, section: @section, title: "Archive filter", body: "OP", ip_address: "127.0.0.1").value
    Community::ModerateTopic.call(user: @mod, topic: @topic, action: "archive")
    @helper = Class.new { include Community::TopicFilterable }.new
  end

  test "archived filter for staff" do
    scope = @helper.send(:apply_topic_filter, Community::Topic.where(status: :published), filter: "archived", user: @mod)
    assert_includes scope.pluck(:id), @topic.id
  end

  test "is:archived parsed from search query" do
    result = Community::ParseSearchQuery.call(query: "is:archived bugs")
    assert result.success?
    assert_equal "archived", result.value[:archived_filter]
    assert_equal "bugs", result.value[:query]
  end
end

class Community::DismissGlobalAnnouncementTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r52-ann") { |c| c.name = "A" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r52-ann-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @user, section: @section, title: "Ann", body: "OP", ip_address: "127.0.0.1").value
    @topic.update!(global_announcement: true)
  end

  test "dismiss stores topic public id" do
    result = Community::DismissGlobalAnnouncement.call(user: @user, topic_public_id: @topic.public_id)
    assert result.success?
    assert_includes @user.reload.dismissed_global_announcement_ids, @topic.public_id
  end
end

class Community::HighlightSearchTextTest < ActiveSupport::TestCase
  test "highlights query terms" do
    result = Community::HighlightSearchText.call(text: "hello world", query: "world")
    assert result.success?
    assert_includes result.value[:html], "<mark>world</mark>"
  end
end

class Community::OpenScheduledTopicTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r52-open") { |c| c.name = "O" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r52-open-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @user, section: @section, title: "Open", body: "OP", ip_address: "127.0.0.1").value
    @topic.update!(locked: true, auto_open_at: 1.minute.ago)
  end

  test "unlocks topic when auto_open_at passed" do
    result = Community::OpenScheduledTopic.call(topic: @topic)
    assert result.success?
    @topic.reload
    assert_not @topic.locked?
    assert_nil @topic.auto_open_at
  end
end

class Commerce::ShippingDeliveryEstimateTest < ActiveSupport::TestCase
  test "delivery estimate label" do
    label = Commerce::ShippingMethods.delivery_estimate_label(
      "code" => "standard", "label" => "标准", "cents" => 800, "delivery_days_min" => 3, "delivery_days_max" => 5
    )
    assert_equal "预计 3-5 天送达", label
  end
end

class Commerce::PartialRefundRequestTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_partial_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "paid",
      subtotal_cents: 10000,
      total_cents: 10000,
      currency: "CNY"
    )
    Payments::Record.create!(
      order: @order,
      provider: "fake",
      amount_cents: 10000,
      currency: "CNY",
      status: "succeeded"
    )
  end

  test "customer can request partial refund" do
    result = Commerce::RequestRefund.call(order: @order, user: @user, amount_cents: 3000, reason: "partial")
    assert result.success?, result.error
    assert_equal 3000, result.value.amount_cents
  end

  test "rejects amount above max" do
    result = Commerce::RequestRefund.call(order: @order, user: @user, amount_cents: 20000)
    assert result.failure?
  end
end

class Commerce::WebhookHmacTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_hmac_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "paid",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY"
    )
    SiteSetting.set("store.order_webhook_url", "https://example.com/hooks")
    SiteSetting.set("store.order_webhook_secret", "test-secret")
  end

  teardown do
    SiteSetting.set("store.order_webhook_url", "")
    SiteSetting.set("store.order_webhook_secret", "")
  end

  test "passes secret to webhook job" do
    assert_enqueued_jobs 1, only: Commerce::DispatchOrderWebhookJob do
      Commerce::DispatchOrderWebhook.call(order: @order, event_type: "order.test")
    end
    job = enqueued_jobs.find { |j| j["job_class"] == "Commerce::DispatchOrderWebhookJob" }
    assert_equal "test-secret", job["arguments"][2]
  end
end

class Commerce::ShippedWebhookTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @admin = create_user
    grant_permission(@admin, "store.orders.manage")
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_ship_#{SecureRandom.hex(4)}",
      name: "Physical",
      slug: "phys-#{SecureRandom.hex(4)}",
      product_type: "physical",
      status: "active",
      price_cents: 1000,
      currency: "CNY",
      requires_shipping: true
    )
    @order = Commerce::Order.create!(
      public_id: "ord_ship_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "paid",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY"
    )
    Commerce::OrderItem.create!(
      order: @order,
      product: @product,
      product_name: @product.name,
      unit_price_cents: 1000,
      quantity: 1,
      total_cents: 1000,
      fulfillment_snapshot: { product_type: "physical" }
    )
    SiteSetting.set("store.order_webhook_url", "https://example.com/hooks")
  end

  teardown do
    SiteSetting.set("store.order_webhook_url", "")
  end

  test "mark shipped dispatches order.shipped webhook" do
    assert_enqueued_with(job: Commerce::DispatchOrderWebhookJob) do
      Commerce::UpdateOrderShipping.call(
        order: @order,
        actor: @admin,
        tracking_number: "TN123",
        shipping_carrier: "SF",
        mark_shipped: true
      )
    end
  end
end

class Commerce::MerchantReviewReplyTest < ActiveSupport::TestCase
  setup do
    @staff = create_user
    grant_permission(@staff, "store.products.manage")
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_rev_#{SecureRandom.hex(4)}",
      name: "Review Product",
      slug: "rev-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY"
    )
    @review = Commerce::Review.create!(user: @user, product: @product, rating: 5, body: "Great", status: "published")
  end

  test "staff can reply to review" do
    result = Commerce::ReplyToReview.call(review: @review, actor: @staff, body: "Thank you!")
    assert result.success?
    assert_equal "Thank you!", @review.reload.merchant_reply
  end
end

class Commerce::RecoveryCartCouponTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @cart = Commerce::Cart.create!(user: @user)
  end

  test "recovery url includes coupon" do
    url = @cart.recovery_cart_url(coupon: "SAVE10")
    assert_includes url, "coupon=SAVE10"
    assert_includes url, "recovery=#{@cart.recovery_token}"
  end
end

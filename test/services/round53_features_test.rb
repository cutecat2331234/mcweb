# frozen_string_literal: true

require "test_helper"

class Community::ProcessHashtagsTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r53-hash") { |c| c.name = "H" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r53-hash-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @user, section: @section, title: "Tags", body: "Hello #ruby #rails", ip_address: "127.0.0.1").value
  end

  test "syncs hashtags from body to topic tags" do
    assert_includes @topic.reload.tags.pluck(:name), "ruby"
    assert_includes @topic.tags.pluck(:name), "rails"
  end

  test "merges hashtags on reply without dropping existing" do
    Community::CreatePost.call(user: @user, topic: @topic, body: "More #discourse", ip_address: "127.0.0.1", skip_interval_check: true)
    names = @topic.reload.tags.pluck(:name)
    assert_includes names, "ruby"
    assert_includes names, "discourse"
  end
end

class Community::HereMentionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @author = create_user
    @participant = create_user
    category = Community::Category.find_or_create_by!(slug: "r53-here") { |c| c.name = "H" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r53-here-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @author, section: @section, title: "Here", body: "OP", ip_address: "127.0.0.1").value
    Community::CreatePost.call(user: @participant, topic: @topic, body: "Reply", ip_address: "127.0.0.1", skip_interval_check: true)
    Community::CreatePost.call(user: @author, topic: @topic, body: "Ping @here", ip_address: "127.0.0.1", skip_interval_check: true)
  end

  test "@here notifies topic participants except author" do
    assert Notification.exists?(user: @participant, notification_type: "forum.mention")
    assert_not Notification.exists?(user: @author, notification_type: "forum.mention")
  end
end

class Community::SectionDefaultTagsTest < ActiveSupport::TestCase
  setup do
    @tag = Community::Tag.find_or_create_by!(slug: "r53-default") { |t| t.name = "default-tag" }
    category = Community::Category.find_or_create_by!(slug: "r53-def") { |c| c.name = "D" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r53-def-sec") do |s|
      s.name = "S"
      s.position = 0
      s.default_tag_ids = [ @tag.id ]
    end
  end

  test "section exposes default tag names" do
    assert_equal [ "default-tag" ], @section.default_tags.pluck(:name)
  end
end

class Community::CategoryRssTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r53-rss") { |c| c.name = "RSS Cat" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r53-rss-sec") { |s| s.name = "S"; s.position = 0 }
    Community::CreateTopic.call(user: @user, section: @section, title: "Feed topic", body: "OP", ip_address: "127.0.0.1")
  end

  test "category rss feed renders" do
    get forum_category_rss_path(slug: "r53-rss"), as: :rss
    assert_response :success
    assert_includes response.body, "Feed topic"
    assert_includes response.body, forum_category_path(slug: "r53-rss")
  end

  test "category show page renders" do
    get forum_category_path(slug: "r53-rss")
    assert_response :success
  end
end

class Community::TopicListExcerptTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    suffix = SecureRandom.hex(4)
    category = Community::Category.find_or_create_by!(slug: "r53-excerpt-#{suffix}") { |c| c.name = "E" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r53-excerpt-sec-#{suffix}") { |s| s.name = "S"; s.position = 0 }
    result = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Thumb",
      body: "Preview text for excerpt",
      ip_address: "127.0.0.1"
    )
    assert result.success?, result.error
    @topic = result.value
    @topic.posts.order(:floor_number).first.update!(body: "Preview text ![img](https://example.com/pic.png)")
    @helper = Class.new do
      include InertiaSerializable
      include Rails.application.routes.url_helpers

      def current_user
        nil
      end
    end.new
  end

  test "serializes excerpt and thumbnail" do
    assert_includes @helper.send(:topic_list_excerpt, @topic), "Preview"
    assert_equal "https://example.com/pic.png", @helper.send(:topic_list_thumbnail, @topic)
  end
end

class Commerce::RefundWindowTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_window_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "paid",
      subtotal_cents: 5000,
      total_cents: 5000,
      currency: "CNY"
    )
    Payments::Record.create!(
      order: @order,
      provider: "fake",
      amount_cents: 5000,
      currency: "CNY",
      status: "succeeded",
      created_at: 10.days.ago
    )
    SiteSetting.set("store.refund_window_days", "7")
  end

  teardown do
    SiteSetting.set("store.refund_window_days", "0")
  end

  test "rejects refund outside window" do
    result = Commerce::RequestRefund.call(order: @order, user: @user, reason: "late")
    assert result.failure?
    assert_equal "Refund window has expired.", result.error
  end

  test "allows refund inside window" do
    @order.payment_records.update_all(created_at: 2.days.ago)
    result = Commerce::RequestRefund.call(order: @order, user: @user, reason: "ok")
    assert result.success?, result.error
  end
end

class Commerce::PendingOrderExpiryTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    SiteSetting.set("store.pending_order_expiry_minutes", "15")
    @order = Commerce::Order.create!(
      public_id: "ord_exp_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY",
      created_at: 20.minutes.ago
    )
  end

  teardown do
    SiteSetting.set("store.pending_order_expiry_minutes", "30")
  end

  test "expire job cancels old pending orders" do
    Commerce::ExpirePendingOrdersJob.perform_now
    assert_equal "cancelled", @order.reload.status
  end
end

class Commerce::WebhookItemsPayloadTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_items_#{SecureRandom.hex(4)}",
      name: "Item Product",
      slug: "items-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 1500,
      currency: "CNY"
    )
    @order = Commerce::Order.create!(
      public_id: "ord_items_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "paid",
      subtotal_cents: 1500,
      total_cents: 1500,
      currency: "CNY"
    )
    Commerce::OrderItem.create!(
      order: @order,
      product: @product,
      product_name: @product.name,
      unit_price_cents: 1500,
      quantity: 1,
      total_cents: 1500,
      fulfillment_snapshot: { product_type: "virtual" }
    )
    SiteSetting.set("store.order_webhook_url", "https://example.com/hooks")
  end

  teardown do
    SiteSetting.set("store.order_webhook_url", "")
  end

  test "webhook payload includes line items" do
    assert_enqueued_jobs 1, only: Commerce::DispatchOrderWebhookJob do
      Commerce::DispatchOrderWebhook.call(order: @order, event_type: "order.paid")
    end
    job = enqueued_jobs.find { |j| j["job_class"] == "Commerce::DispatchOrderWebhookJob" }
    payload = job["arguments"][1]
    assert_equal 1500, payload["subtotal_cents"]
    assert_equal 1, payload["items"].size
    assert_equal "Item Product", payload["items"].first["product_name"]
  end
end

class Commerce::MerchantReviewReplyNotifyTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @staff = create_user
    grant_permission(@staff, "store.products.manage")
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_mrr_#{SecureRandom.hex(4)}",
      name: "Notify Product",
      slug: "mrr-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY"
    )
    @review = Commerce::Review.create!(user: @user, product: @product, rating: 5, body: "Nice", status: "published")
  end

  test "reply notifies customer in app" do
    assert_difference -> { Notification.where(user: @user, notification_type: "commerce.merchant_review_reply").count }, 1 do
      Commerce::ReplyToReview.call(review: @review, actor: @staff, body: "Thanks!")
    end
  end
end

class Commerce::CategoryProductCountTest < ActiveSupport::TestCase
  setup do
    @category = Commerce::Category.find_or_create_by!(slug: "r53-store-cat") { |c| c.name = "Count Cat" }
    Commerce::Product.create!(
      public_id: "prod_cnt_#{SecureRandom.hex(4)}",
      name: "Counted",
      slug: "cnt-#{SecureRandom.hex(4)}",
      category: @category,
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY"
    )
    @helper = Class.new do
      include InertiaSerializable
      include Rails.application.routes.url_helpers
    end.new
  end

  test "serialize_category includes product_count" do
    props = @helper.send(:serialize_category, @category)
    assert_operator props[:product_count], :>=, 1
  end
end

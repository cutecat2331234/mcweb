# frozen_string_literal: true

require "test_helper"

class Round90FollowedUserReplyTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @author = create_user
    @follower = create_user
    Community::UserFollow.create!(follower: @follower, followed: @author)
    NotificationPreference.set!(@follower, channel: "in_app", notification_type: "forum.followed_reply", enabled: true)
    category = Community::Category.find_or_create_by!(slug: "r90-reply") { |c| c.name = "R" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r90-reply-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(
      user: @author,
      section: section,
      title: "Follow reply #{SecureRandom.hex(4)}",
      body: "OP body content",
      ip_address: "127.0.0.1"
    ).value
  end

  test "notifies follower when followed user replies" do
    replier = @author
    result = Community::CreatePost.call(
      user: replier,
      topic: @topic,
      body: "My reply here",
      ip_address: "127.0.0.1",
      skip_interval_check: true
    )
    assert result.success?, result.error || result.errors.inspect

    assert Notification.exists?(user: @follower, notification_type: "forum.followed_reply")
  end

  test "skips notification when preference disabled" do
    NotificationPreference.set!(@follower, channel: "in_app", notification_type: "forum.followed_reply", enabled: false)
    Community::CreatePost.call(
      user: @author,
      topic: @topic,
      body: "Another reply",
      ip_address: "127.0.0.1",
      skip_interval_check: true
    )

    assert_not Notification.exists?(user: @follower, notification_type: "forum.followed_reply")
  end
end

class Round90FollowedTopicEmailTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @author = create_user
    @follower = create_user
    @follower.update!(forum_watch_email_mode: "instant")
    Community::UserFollow.create!(follower: @follower, followed: @author)
    NotificationPreference.set!(@follower, channel: "email", notification_type: "forum.followed_topic", enabled: true)
    category = Community::Category.find_or_create_by!(slug: "r90-email") { |c| c.name = "E" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r90-email-sec") { |s| s.name = "S"; s.position = 0 }
  end

  test "sends email when followed user creates topic" do
    topic = Community::CreateTopic.call(
      user: @author,
      section: @section,
      title: "Email topic #{SecureRandom.hex(4)}",
      body: "Body content here",
      ip_address: "127.0.0.1"
    ).value
    assert topic

    assert_enqueued_jobs 1, only: MailDeliveryJob do
      Community::NotifyFollowedUserTopic.call(topic: topic)
    end
  end
end

class Round90TopicRssTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r90-rss") { |c| c.name = "R" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r90-rss-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(
      user: @user,
      section: section,
      title: "RSS topic #{SecureRandom.hex(4)}",
      body: "First post body",
      ip_address: "127.0.0.1"
    ).value
  end

  test "topic rss returns posts as items" do
    get forum_topic_rss_path(id: @topic.public_id, format: :rss)
    assert_response :success
    assert_includes response.body, "<rss"
    assert_includes response.body, @topic.title
    assert_includes response.body, "First post body"
  end

  test "topic show includes rss_url" do
    get forum_topic_path(@topic)
    assert_response :success
    assert_includes response.body, "rss_url"
  end
end

class Round90OrderCreatedWebhookTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    SiteSetting.set("store.order_webhook_url", "https://example.com/hook")
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_r90_#{SecureRandom.hex(4)}",
      name: "Test",
      slug: "test-r90-#{SecureRandom.hex(4)}",
      price_cents: 1000,
      currency: "CNY",
      product_type: "virtual",
      status: "active"
    )
    cart = Commerce::Cart.create!(user: @user)
    cart.add_item!(product: @product, quantity: 1)
    @cart = cart
  end

  test "create order dispatches order.created webhook" do
    assert_enqueued_jobs 1, only: Commerce::DispatchOrderWebhookJob do
      result = Commerce::CreateOrder.call(cart: @cart, user: @user)
      assert result.success?, result.error || result.errors.inspect
    end

    job = enqueued_jobs.find { |j| j["job_class"] == "Commerce::DispatchOrderWebhookJob" }
    assert_equal "order.created", job["arguments"][1]["event"]
  end
end

class Round90OrderPaidWebhookTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    SiteSetting.set("store.order_webhook_url", "https://example.com/hook")
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_r90_paid_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "awaiting_payment",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY"
    )
  end

  test "mark_paid dispatches order.paid webhook" do
    assert_enqueued_jobs 1, only: Commerce::DispatchOrderWebhookJob do
      @order.mark_paid!
    end

    job = enqueued_jobs.find { |j| j["job_class"] == "Commerce::DispatchOrderWebhookJob" }
    assert_equal "order.paid", job["arguments"][1]["event"]
  end
end

class Round90ExpireOrderReasonTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    SiteSetting.set("store.order_webhook_url", "https://example.com/hook")
    SiteSetting.set("store.pending_order_expiry_minutes", "30")
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_r90_exp_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY",
      created_at: 31.minutes.ago
    )
  end

  test "expire job cancels with expired reason" do
    assert_enqueued_jobs 1, only: Commerce::DispatchOrderWebhookJob do
      Commerce::ExpirePendingOrdersJob.perform_now
    end

    @order.reload
    assert_equal "cancelled", @order.status
    job = enqueued_jobs.find { |j| j["job_class"] == "Commerce::DispatchOrderWebhookJob" }
    payload = job["arguments"][1]
    assert_equal "order.cancelled", payload["event"]
    assert_equal "expired", payload["cancel_reason"]
  end
end

class Round90PaymentExpiresAtTest < ActiveSupport::TestCase
  setup do
    SiteSetting.set("store.pending_order_expiry_minutes", "30")
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_r90_pay_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY",
      created_at: 10.minutes.ago
    )
    @helper = Object.new.extend(InertiaSerializable)
  end

  test "payment expiry helpers for pending order" do
    assert @helper.send(:payment_expires_at, @order).future?
    assert_not @helper.send(:payment_expired?, @order)
    assert @helper.send(:payment_actionable?, @order)
  end

  test "expired pending order is not actionable" do
    @order.update!(created_at: 31.minutes.ago)
    assert @helper.send(:payment_expired?, @order)
    assert_not @helper.send(:payment_actionable?, @order)
  end
end

class Round90BatchTestOrderWebhooksTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    SiteSetting.set("store.order_webhook_url", "https://example.com/hook")
  end

  test "batch test queues all event types" do
    total = Commerce::DispatchTestOrderWebhook::EVENT_TYPES.size
    assert_enqueued_jobs total, only: Commerce::DispatchOrderWebhookJob do
      result = Commerce::BatchTestOrderWebhooks.call
      assert result.success?
      assert_equal total, result.value[:queued]
    end
  end
end

class Round90StoreWebhookKindFilterTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
    Commerce::OrderWebhookDelivery.create!(
      event_type: "order.test",
      url: "https://example.com/hook",
      status: "success",
      response_code: 200,
      request_payload: { "event" => "order.test", "test" => true }
    )
    Commerce::OrderWebhookDelivery.create!(
      event_type: "order.created",
      order_public_id: "ord_real",
      url: "https://example.com/hook",
      status: "success",
      response_code: 200,
      request_payload: { "event" => "order.created", "order_id" => "ord_real" }
    )
  end

  test "store webhook deliveries filter by test kind" do
    sign_in_as(@admin)
    get admin_store_webhook_deliveries_path(kind: "test")
    assert_response :success
    assert_includes response.body, "kindTabs"
  end
end

class Round90CancelOrderSingleWebhookTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    SiteSetting.set("store.order_webhook_url", "https://example.com/hook")
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_r90_cancel_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY"
    )
  end

  test "cancel order sends single order.cancelled webhook" do
    assert_enqueued_jobs 1, only: Commerce::DispatchOrderWebhookJob do
      Commerce::CancelOrder.call(order: @order, actor: @user, reason: "test")
    end

    job = enqueued_jobs.find { |j| j["job_class"] == "Commerce::DispatchOrderWebhookJob" }
    assert_equal "order.cancelled", job["arguments"][1]["event"]
  end
end

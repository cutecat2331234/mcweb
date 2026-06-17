# frozen_string_literal: true

require "test_helper"

class Community::UnsolveTopicTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "unsolve-cat") { |c| c.name = "Unsolve" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "unsolve-sec") do |s|
      s.name = "Unsolve Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Solved topic",
      body: "Body",
      ip_address: "127.0.0.1"
    ).value
    @post = @topic.posts.first
    Community::MarkTopicSolved.call(user: @user, topic: @topic, post: @post)
  end

  test "unsolves topic" do
    result = Community::UnsolveTopic.call(user: @user, topic: @topic)
    assert result.success?
    assert_nil @topic.reload.solved_post_id
  end
end

class Community::TopicFilterTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "filter-cat") { |c| c.name = "Filter" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "filter-sec") do |s|
      s.name = "Filter Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Filter topic",
      body: "Body",
      ip_address: "127.0.0.1"
    ).value
  end

  test "unsolved filter excludes solved topics" do
    helper = Class.new { include Community::TopicFilterable }.new
    scope = Community::Topic.where(status: :published)
    unsolved = helper.send(:apply_topic_filter, scope, filter: "unsolved", user: @user)
    assert_includes unsolved.pluck(:id), @topic.id

    Community::MarkTopicSolved.call(user: @user, topic: @topic, post: @topic.posts.first)
    unsolved = helper.send(:apply_topic_filter, scope, filter: "unsolved", user: @user)
    assert_not_includes unsolved.pluck(:id), @topic.id
  end
end

class Commerce::VariantRequiredTest < ActiveSupport::TestCase
  test "variant required when product has variants" do
    user = create_user
    product = Commerce::Product.create!(
      public_id: "prod_var_req_#{SecureRandom.hex(4)}",
      name: "Variant Required",
      slug: "variant-required-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 10
    )
    product.variants.create!(name: "A", sku: "A-1", price_cents: 100, stock: 5)

    result = Commerce::ValidateCartItem.call(user: user, product: product, variant: nil, quantity: 1)
    assert result.failure?
  end
end

class Commerce::RefundCouponRestoreTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_ref_coupon_#{SecureRandom.hex(4)}",
      name: "Refund Coupon",
      slug: "refund-coupon-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 1000,
      currency: "CNY",
      stock: 10
    )
    @coupon = Commerce::Coupon.create!(
      code: "REFUND#{SecureRandom.hex(2).upcase}",
      discount_type: "fixed",
      discount_value: 100,
      active: true
    )
    cart = Commerce::Cart.create!(user: @user)
    Commerce::CartItem.create!(cart: cart, product: @product, quantity: 1)
    @order = Commerce::CreateOrder.call(cart: cart, user: @user, coupon_code: @coupon.code).value
    @order.update!(status: "paid")
    @payment = Payments::Record.create!(
      order: @order,
      provider: "fake",
      amount_cents: @order.total_cents,
      currency: "CNY",
      status: "succeeded"
    )
  end

  test "full refund restores coupon usage" do
    assert_equal 1, @coupon.reload.used_count
    result = Commerce::ProcessRefund.call(
      order: @order,
      payment_record: @payment,
      amount_cents: @payment.amount_cents,
      approved_by: @user
    )
    assert result.success?
    assert_equal 0, @coupon.reload.used_count
  end
end

class Minecraft::TaskDispatcherFailureTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @server = Minecraft::Server.create!(
      public_id: "srv_#{SecureRandom.alphanumeric(12)}",
      name: "Test",
      address: "127.0.0.1",
      port: 25565,
      status: "online"
    )
    @product = Commerce::Product.create!(
      public_id: "prod_fail_#{SecureRandom.hex(4)}",
      name: "Fail Product",
      slug: "fail-product-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      stock: 5
    )
    cart = Commerce::Cart.create!(user: @user)
    Commerce::CartItem.create!(cart: cart, product: @product, quantity: 1)
    order = Commerce::CreateOrder.call(cart: cart, user: @user).value
    order.update!(status: "paid")
    @fulfillment = Commerce::CreateFulfillment.call(order_item: order.items.first).value
    @task = Minecraft::ConnectorTask.create!(
      server: @server,
      fulfillment: @fulfillment,
      task_type: "deliver_item",
      delivery_id: @fulfillment.delivery_id,
      status: "claimed",
      payload: {}
    )
  end

  test "failed delivery marks fulfillment failed" do
    result = Minecraft::TaskDispatcher.call(
      server: @server,
      task: @task,
      result: { success: false, error: "player offline" },
      action: :complete
    )
    assert result.success?
    assert_equal "failed", @fulfillment.reload.status
    assert_includes @fulfillment.last_error, "player offline"
  end
end

class Community::NotificationVisitTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in_as(@user)
    @notification = Notification.notify!(
      user: @user,
      notification_type: "forum.topic_reply",
      title: "Test",
      body: "Body",
      metadata: { path: "/app/forum/sections" }
    )
  end

  test "visit marks notification read and redirects" do
    get visit_forum_notification_path(@notification)
    assert_response :redirect
    assert @notification.reload.read?
  end

  test "visit rejects unsafe notification destinations" do
    @notification.update!(metadata: { path: "//evil.com" })

    get visit_forum_notification_path(@notification)

    assert_redirected_to forum_notifications_path
    assert @notification.reload.read?
  end
end

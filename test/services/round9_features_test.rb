# frozen_string_literal: true

require "test_helper"

class Community::SlowModeRouteTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    grant_permission(@user, "forum.topics.lock")
    sign_in_as(@user)
    category = Community::Category.find_or_create_by!(slug: "slow-cat") { |c| c.name = "Slow" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "slow-sec") do |s|
      s.name = "Slow Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Slow mode topic",
      body: "Body text",
      ip_address: "127.0.0.1"
    ).value
  end

  test "slow mode patch updates topic" do
    patch slow_mode_forum_topic_path(@topic), params: { seconds: 60 }
    assert_response :redirect
    assert_equal 60, @topic.reload.slow_mode_seconds
  end
end

class Community::MarkAllTopicsReadTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "read-cat") { |c| c.name = "Read" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "read-sec") do |s|
      s.name = "Read Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Unread topic",
      body: "Hello",
      ip_address: "127.0.0.1"
    ).value
    Community::CreatePost.call(user: @user, topic: @topic, body: "Reply one")
    Community::ReadState.mark_read!(@user, @topic, floor: 1)
  end

  test "marks all topics read" do
    result = Community::MarkAllTopicsRead.call(user: @user)
    assert result.success?
    state = Community::ReadState.find_by(user: @user, topic: @topic)
    assert_equal @topic.posts.maximum(:floor_number), state.last_read_floor
  end
end

class Community::PollClosesAtTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "poll-cat") { |c| c.name = "Poll" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "poll-sec") do |s|
      s.name = "Poll Sec"
      s.position = 0
    end
  end

  test "creates poll with closes_at" do
    result = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Poll topic",
      body: "Vote please",
      poll_question: "Favorite?",
      poll_options: %w[A B],
      poll_closes_days: 7,
      ip_address: "127.0.0.1"
    )
    assert result.success?
    poll = result.value.poll
    assert poll.closes_at.present?
    assert poll.closes_at > 6.days.from_now
  end
end

class Commerce::CancelOrderCouponTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_coupon_#{SecureRandom.hex(4)}",
      name: "Coupon Product",
      slug: "coupon-product-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 1000,
      currency: "CNY",
      stock: 10
    )
    @coupon = Commerce::Coupon.create!(
      code: "SAVE10#{SecureRandom.hex(2).upcase}",
      discount_type: "fixed",
      discount_value: 100,
      active: true
    )
    cart = Commerce::Cart.create!(user: @user)
    Commerce::CartItem.create!(cart: cart, product: @product, quantity: 1)
    @order = Commerce::CreateOrder.call(cart: cart, user: @user, coupon_code: @coupon.code).value
  end

  test "cancel restores coupon usage" do
    assert_equal 1, @coupon.reload.used_count
    result = Commerce::CancelOrder.call(order: @order, actor: @user)
    assert result.success?
    assert_equal 0, @coupon.reload.used_count
  end
end

class Commerce::SyncOrderFulfillmentStatusTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_ful_#{SecureRandom.hex(4)}",
      name: "Fulfill Product",
      slug: "fulfill-product-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      stock: 5
    )
    cart = Commerce::Cart.create!(user: @user)
    Commerce::CartItem.create!(cart: cart, product: @product, quantity: 1)
    @order = Commerce::CreateOrder.call(cart: cart, user: @user).value
    @order.update!(status: "paid")
    @item = @order.items.first
    @fulfillment = Commerce::CreateFulfillment.call(order_item: @item).value
  end

  test "marks order fulfilled when all items fulfilled" do
    @fulfillment.update!(status: "fulfilled", fulfilled_at: Time.current)
    result = Commerce::SyncOrderFulfillmentStatus.call(order: @order)
    assert result.success?
    assert_equal "completed", @order.reload.status
  end
end

class Commerce::ProductVariantStockTest < ActiveSupport::TestCase
  test "in_stock checks variants when present" do
    product = Commerce::Product.create!(
      public_id: "prod_var_#{SecureRandom.hex(4)}",
      name: "Variant Product",
      slug: "variant-product-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 0
    )
    product.variants.create!(name: "A", sku: "A-1", price_cents: 100, stock: 3)
    assert product.in_stock?
  end
end

class Commerce::RetryFulfillmentTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_retry_#{SecureRandom.hex(4)}",
      name: "Retry Product",
      slug: "retry-product-#{SecureRandom.hex(4)}",
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
    @fulfillment.update!(status: "failed", last_error: "timeout")
  end

  test "retry resets fulfillment to pending" do
    result = Commerce::RetryFulfillment.call(fulfillment: @fulfillment)
    assert result.success?
    assert_equal "pending", @fulfillment.reload.status
    assert_nil @fulfillment.last_error
  end

  test "retry supersedes pending connector task before re-dispatch" do
    server = Minecraft::Server.create!(
      public_id: "srv_retry_#{SecureRandom.hex(4)}",
      name: "Retry Server",
      connector_secret: "secret_#{SecureRandom.hex(8)}"
    )
    task = Minecraft::ConnectorTask.create!(
      server: server,
      fulfillment: @fulfillment,
      task_type: "deliver_item",
      delivery_id: @fulfillment.delivery_id,
      status: "pending",
      payload: { "commands" => [ "say stuck" ] }
    )

    assert_enqueued_with(job: Minecraft::EnsureInstanceRunningJob, args: [ @fulfillment.id ]) do
      result = Commerce::RetryFulfillment.call(fulfillment: @fulfillment)
      assert result.success?
    end

    assert_equal "failed", task.reload.status
    assert_equal "superseded_by_retry", task.result["error"]
  end

  test "rejects retry when order is refunded" do
    @fulfillment.order.update!(status: "refunded")

    result = Commerce::RetryFulfillment.call(fulfillment: @fulfillment)

    assert result.failure?
    assert_equal "failed", @fulfillment.reload.status
  end
end

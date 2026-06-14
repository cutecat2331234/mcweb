# frozen_string_literal: true

require "test_helper"

class Community::ToggleUserFollowTest < ActiveSupport::TestCase
  setup do
    @follower = create_user
    @followed = create_user
  end

  test "follows and unfollows user" do
    result = Community::ToggleUserFollow.call(follower: @follower, followed_username: @followed.username)
    assert result.success?
    assert result.value[:following]
    assert Community::UserFollow.exists?(follower: @follower, followed: @followed)

    result = Community::ToggleUserFollow.call(follower: @follower, followed_username: @followed.username)
    assert result.success?
    assert_not result.value[:following]
    assert_not Community::UserFollow.exists?(follower: @follower, followed: @followed)
  end

  test "cannot follow yourself" do
    result = Community::ToggleUserFollow.call(follower: @follower, followed_username: @follower.username)
    assert result.failure?
  end
end

class Community::NotifyFollowedUserTopicTest < ActiveSupport::TestCase
  setup do
    @author = create_user
    @follower = create_user
    Community::UserFollow.create!(follower: @follower, followed: @author)
    category = Community::Category.find_or_create_by!(slug: "follow-cat") { |c| c.name = "Follow" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "follow-sec") do |s|
      s.name = "Follow Sec"
      s.position = 0
    end
  end

  test "notifies followers of new topic" do
    topic = Community::CreateTopic.call(
      user: @author,
      section: @section,
      title: "Followed topic #{SecureRandom.hex(4)}",
      body: "Hello followers",
      ip_address: "127.0.0.1"
    ).value

    assert topic
    notification = @follower.notifications.find_by(notification_type: "forum.followed_topic")
    assert notification
    assert_includes notification.title, @author.username
  end
end

class Community::SendForumDigestTest < ActiveSupport::TestCase
  setup do
    @user = create_user(forum_digest_frequency: "daily")
    @user.notifications.create!(
      notification_type: "forum.topic_reply",
      title: "Reply",
      body: "New reply",
      metadata: { path: "/forum/topics/abc" }
    )
  end

  test "sends digest when due" do
    result = Community::SendForumDigest.call(user: @user)
    assert result.success?
    assert result.value[:sent]
    assert @user.reload.forum_digest_last_sent_at
  end

  test "skips when frequency is none" do
    @user.update!(forum_digest_frequency: "none")
    result = Community::SendForumDigest.call(user: @user)
    assert result.success?
    assert result.value[:skipped]
  end
end

class Commerce::SubscribeStockAlertTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_alert_#{SecureRandom.hex(4)}",
      name: "Alert Product",
      slug: "alert-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 0
    )
  end

  test "subscribes to stock alert" do
    result = Commerce::SubscribeStockAlert.call(user: @user, product: @product)
    assert result.success?
    alert = Commerce::StockAlert.find_by(user: @user, product: @product)
    assert alert
    assert_nil alert.notified_at
  end
end

class Commerce::ProductLowStockTest < ActiveSupport::TestCase
  test "detects low stock on product and variant" do
    product = Commerce::Product.create!(
      public_id: "prod_low_#{SecureRandom.hex(4)}",
      name: "Low Stock",
      slug: "low-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: Commerce::SalesMetrics::LOW_STOCK_THRESHOLD
    )
    assert product.low_stock?

    variant_product = Commerce::Product.create!(
      public_id: "prod_var_low_#{SecureRandom.hex(4)}",
      name: "Variant Low",
      slug: "var-low-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY"
    )
    variant = variant_product.variants.create!(
      name: "Size M",
      sku: "sku-#{SecureRandom.hex(6)}",
      price_cents: 100,
      stock: 2
    )
    assert variant.low_stock?
    assert variant_product.low_stock?
  end
end

class Commerce::OrdersSearchTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in_as(@user)
    @order = Commerce::Order.create!(
      user: @user,
      order_number: "ORD-SEARCH-#{SecureRandom.hex(4)}",
      status: "pending",
      subtotal_cents: 500,
      discount_cents: 0,
      total_cents: 500,
      currency: "CNY"
    )
  end

  test "filters orders by query" do
    get store_orders_path, params: { q: @order.order_number }
    assert_response :success
    assert_includes response.body, @order.order_number
  end
end

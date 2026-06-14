# frozen_string_literal: true

require "test_helper"

class Community::CreateTopicFromPostTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @other = create_user
    category = Community::Category.find_or_create_by!(slug: "r47-fork") { |c| c.name = "Fork" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r47-fork-sec") { |s| s.name = "S"; s.position = 0 }
    topic_result = Community::CreateTopic.call(user: @other, section: @section, title: "Source topic", body: "Opening post body", ip_address: "127.0.0.1")
    assert topic_result.success?, topic_result.error
    @topic = topic_result.value
    @post = Community::CreatePost.call(user: @other, topic: @topic, body: "Reply to fork", ip_address: "127.0.0.1", skip_interval_check: true).value
  end

  test "creates topic from post with source link" do
    result = Community::CreateTopicFromPost.call(user: @user, post: @post, title: "Forked topic", body: "My thoughts")
    assert result.success?, result.error
    new_topic = result.value
    assert_equal @post.id, new_topic.source_post_id
    assert_includes new_topic.posts.first.body, "Reply to fork"
    assert_includes new_topic.posts.first.body, @post.user.username
  end
end

class Community::ToggleSectionSubscriptionDefaultLevelTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r47-sub") { |c| c.name = "Sub" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r47-sub-sec") do |s|
      s.name = "S"
      s.position = 0
      s.default_notification_level = "tracking"
    end
  end

  test "uses section default notification level on first subscribe" do
    result = Community::ToggleSectionSubscription.call(user: @user, section: @section)
    assert result.success?
    assert_equal "tracking", result.value[:notification_level]
    sub = Community::Subscription.find_by(user: @user, subscribable: @section)
    assert_equal "tracking", sub.notification_level
  end
end

class Commerce::CategorySeoTest < ActiveSupport::TestCase
  test "category stores seo metadata" do
    category = Commerce::Category.create!(
      name: "SEO Category",
      slug: "seo-cat-#{SecureRandom.hex(4)}",
      seo: { "title" => "Shop Category", "description" => "Browse our items" }
    )
    assert_equal "Shop Category", category.seo["title"]
  end
end

class Commerce::ShippingAddressOrderTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      name: "Physical",
      slug: "physical-#{SecureRandom.hex(4)}",
      product_type: "physical",
      status: "active",
      price_cents: 2000,
      currency: "CNY",
      requires_shipping: true,
      fulfillment_config: { shipping_method: "manual" }
    )
    @cart = Commerce::Cart.create!(user: @user)
    @cart.add_item!(product: @product, quantity: 1)
  end

  test "create order saves shipping address" do
    result = Commerce::CreateOrder.call(
      cart: @cart,
      user: @user,
      shipping_address: {
        "name" => "张三",
        "phone" => "13800000000",
        "line1" => "测试路 1 号",
        "city" => "上海",
        "province" => "上海"
      }
    )
    assert result.success?, result.error
    order = result.value
    assert_equal "张三", order.shipping_address["name"]
    assert_equal "上海", order.shipping_address["city"]
  end
end

class Commerce::CartRecoveryTokenTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @cart = Commerce::Cart.create!(user: @user)
    @product = Commerce::Product.create!(
      name: "Recovery",
      slug: "recovery-#{SecureRandom.hex(4)}",
      product_type: "digital",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      fulfillment_config: { download_url: "https://example.com/a.zip" }
    )
    @cart.add_item!(product: @product, quantity: 1)
  end

  test "cart has recovery token and url" do
    @cart.ensure_recovery_token!
    assert @cart.recovery_token.present?
    assert_includes @cart.recovery_cart_url, @cart.recovery_token
  end
end

class Commerce::CartRecoveryIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @cart = Commerce::Cart.create!(user: @user)
    @product = Commerce::Product.create!(
      name: "Recovery Item",
      slug: "recovery-item-#{SecureRandom.hex(4)}",
      product_type: "digital",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      fulfillment_config: { download_url: "https://example.com/a.zip" }
    )
    @cart.add_item!(product: @product, quantity: 1)
    @cart.ensure_recovery_token!
  end

  test "cart show accepts recovery token" do
    get store_cart_path(recovery: @cart.recovery_token)
    assert_response :success
    assert_includes response.body, "Recovery Item"
  end
end

class Commerce::ReorderSkippedDetailsTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @active = Commerce::Product.create!(
      name: "Active Product",
      slug: "active-#{SecureRandom.hex(4)}",
      product_type: "digital",
      status: "active",
      price_cents: 1000,
      currency: "CNY",
      fulfillment_config: { download_url: "https://example.com/a.zip" }
    )
    @inactive = Commerce::Product.create!(
      name: "Inactive Product",
      slug: "inactive-#{SecureRandom.hex(4)}",
      product_type: "digital",
      status: "archived",
      price_cents: 1000,
      currency: "CNY",
      fulfillment_config: { download_url: "https://example.com/b.zip" }
    )
    Commerce::Cart.where(user: @user).destroy_all
    @order = Commerce::Order.create!(
      public_id: "ord_#{SecureRandom.alphanumeric(16)}",
      order_number: "MC#{Time.current.strftime('%Y%m%d')}#{SecureRandom.hex(4).upcase}",
      user: @user,
      status: "completed",
      currency: "CNY",
      subtotal_cents: 2000,
      total_cents: 2000
    )
    Commerce::OrderItem.create!(
      order: @order,
      product: @active,
      product_name: @active.name,
      unit_price_cents: 1000,
      quantity: 1,
      total_cents: 1000,
      fulfillment_snapshot: {}
    )
    Commerce::OrderItem.create!(
      order: @order,
      product: @inactive,
      product_name: @inactive.name,
      unit_price_cents: 1000,
      quantity: 1,
      total_cents: 1000,
      fulfillment_snapshot: {}
    )
  end

  test "reorder returns detailed skip reasons" do
    result = Commerce::ReorderFromOrder.call(user: @user, order: @order)
    assert result.success?
    assert_equal 1, result.value[:added]
    assert_equal 1, result.value[:skipped].size
    assert_equal "Inactive Product", result.value[:skipped].first[:name]
    assert result.value[:skipped].first[:reason].present?
  end
end

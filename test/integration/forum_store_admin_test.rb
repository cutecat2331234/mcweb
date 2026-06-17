# frozen_string_literal: true

require "test_helper"

class ForumIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @category = Community::Category.find_or_create_by!(slug: "test") { |c| c.name = "Test" }
    @section = Community::Section.find_or_create_by!(category: @category, slug: "general") do |s|
      s.name = "General"
      s.description = "Test section"
      s.position = 0
    end
    sign_in_as(@user)
  end

  test "user can view forum sections and create topic" do
    get forum_sections_path
    assert_response :success

    get forum_section_path(@section)
    assert_response :success

    get new_forum_topic_path(section_id: @section.slug)
    assert_response :success

    assert_difference "Community::Topic.count", 1 do
      post forum_topics_path(section_id: @section.slug), params: {
        topic: { title: "Hello world", body: "This is the opening post." }
      }
    end
    assert_redirected_to forum_topic_path(Community::Topic.last)

    topic = Community::Topic.last
    get forum_topic_path(topic)
    assert_response :success

    posts_before = Community::Post.count
    travel 11.seconds do
      post forum_posts_path, params: { post: { topic_id: topic.public_id, body: "First reply" } }
    end
    assert_equal posts_before + 1, Community::Post.count
    assert_redirected_to %r{/app/forum/topics/#{topic.public_id}}
  end

  test "forum search finds topics" do
    Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "UniqueSearchTerm123",
      body: "Searchable opening post.",
      ip_address: "127.0.0.1"
    )

    get forum_search_path, params: { q: "UniqueSearchTerm123" }
    assert_response :success
    assert_match "UniqueSearchTerm123", response.body
  end
end

class StoreIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @product = Commerce::Product.find_or_create_by!(slug: "test-item") do |p|
      p.name = "Test Item"
      p.product_type = "currency"
      p.status = "active"
      p.price_cents = 1000
      p.currency = "CNY"
      p.fulfillment_config = { commands: [ "give {player} diamond 1" ] }
    end
    sign_in_as(@user)
  end

  test "user can browse store and add to cart" do
    get store_products_path
    assert_response :success

    get store_product_path(@product)
    assert_response :success

    patch store_cart_path, params: { product_id: @product.id, quantity: 1 }
    assert_redirected_to store_cart_path

    get store_cart_path
    assert_response :success
    assert_match @product.name, response.body
  end

  test "checkout creates order from cart" do
    cart = Commerce::Cart.find_or_create_by!(user: @user)
    cart.add_item!(product: @product, quantity: 1)

    get store_checkout_path
    assert_response :success

    assert_difference "Commerce::Order.count", 1 do
      post store_checkout_path, params: { checkout: { provider: "fake" } }
    end
    assert_response :redirect
  end

  test "checkout completes zero total order via order_id" do
    gift_card = Commerce::GiftCard.create!(
      code: "GC#{SecureRandom.alphanumeric(10).upcase}",
      balance_cents: 10_000,
      initial_balance_cents: 10_000,
      currency: "CNY",
      active: true,
      created_by: @user
    )
    cart = Commerce::Cart.find_or_create_by!(user: @user)
    cart.add_item!(product: @product, quantity: 1)
    order = Commerce::CreateOrder.call(
      cart: cart,
      user: @user,
      gift_card_code: gift_card.code
    ).value
    assert_equal 0, order.total_cents

    post store_checkout_path, params: { order_id: order.public_id, checkout: { provider: "fake" } }
    assert_redirected_to store_order_path(order)
    assert_equal "paid", order.reload.status
  end

  test "checkout replaces stale pending payment for zero total order" do
    gift_card = Commerce::GiftCard.create!(
      code: "GC#{SecureRandom.alphanumeric(10).upcase}",
      balance_cents: 10_000,
      initial_balance_cents: 10_000,
      currency: "CNY",
      active: true,
      created_by: @user
    )
    cart = Commerce::Cart.find_or_create_by!(user: @user)
    cart.add_item!(product: @product, quantity: 1)
    order = Commerce::CreateOrder.call(
      cart: cart,
      user: @user,
      gift_card_code: gift_card.code
    ).value
    stale = Payments::Record.create!(
      order: order,
      provider: "fake",
      amount_cents: order.subtotal_cents,
      currency: "CNY",
      status: "pending"
    )

    post store_checkout_path, params: { order_id: order.public_id, checkout: { provider: "fake" } }

    assert_redirected_to store_order_path(order)
    assert_equal "failed", stale.reload.status
    assert_equal "paid", order.reload.status
    assert Payments::Record.exists?(order: order, status: "succeeded", amount_cents: 0)
  end

  test "checkout replaces stale pending payment amount on retry" do
    cart = Commerce::Cart.find_or_create_by!(user: @user)
    cart.add_item!(product: @product, quantity: 1)
    order = Commerce::CreateOrder.call(cart: cart, user: @user).value
    order.submit_payment! if order.may_submit_payment?
    stale = Payments::Record.create!(
      order: order,
      provider: "fake",
      amount_cents: order.total_cents + 500,
      currency: "CNY",
      status: "pending"
    )

    post store_checkout_path, params: { order_id: order.public_id, checkout: { provider: "fake" } }

    assert_response :redirect
    assert_equal "failed", stale.reload.status
    active = order.payment_records.pending.order(created_at: :desc).first
    assert_equal order.total_cents, active.amount_cents
  end
end

class AdminIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "store.orders.read")
    sign_in_as(@admin)
  end

  test "admin can access dashboard and orders" do
    get admin_root_path
    assert_response :success

    get admin_store_orders_path
    assert_response :success
  end

  test "read-only admin cannot change order status" do
    customer = create_user
    order = Commerce::Order.create!(
      public_id: "ord_admin_status_#{SecureRandom.hex(4)}",
      order_number: "ORD-ADMIN-#{SecureRandom.hex(4)}",
      user: customer,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 1000,
      discount_cents: 0,
      currency: "CNY"
    )

    patch admin_store_order_path(order), params: { order: { status: "paid", notes: "free order" } }
    assert_redirected_to admin_store_order_path(order)
    assert_equal "pending", order.reload.status
    assert_equal "free order", order.notes
  end

  test "non-admin cannot access admin" do
    delete identity_session_path
    other = create_user
    sign_in_as(other)

    get admin_root_path
    assert_redirected_to root_path
  end
end

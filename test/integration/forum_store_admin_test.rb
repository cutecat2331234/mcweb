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
      post forum_topics_path(section_id: @section.slug), params: { topic: { title: "Hello world" } }
    end
    assert_redirected_to forum_topic_path(Community::Topic.last)

    topic = Community::Topic.last
    get forum_topic_path(topic)
    assert_response :success

    posts_before = Community::Post.count
    post forum_posts_path, params: { post: { topic_id: topic.public_id, body: "First reply" } }
    assert_equal posts_before + 1, Community::Post.count
    assert_redirected_to %r{/forum/topics/#{topic.public_id}}
  end

  test "forum search finds topics" do
    Community::CreateTopic.call(user: @user, section: @section, title: "UniqueSearchTerm123", ip_address: "127.0.0.1")

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

  test "non-admin cannot access admin" do
    delete identity_session_path
    other = create_user
    sign_in_as(other)

    get admin_root_path
    assert_redirected_to root_path
  end
end

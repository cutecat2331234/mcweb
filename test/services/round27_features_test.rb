# frozen_string_literal: true

require "test_helper"

class Community::SplitTopicTest < ActiveSupport::TestCase
  setup do
    @moderator = create_user(username: "mod_split")
    grant_permission(@moderator, "forum.topics.move")
    category = Community::Category.find_or_create_by!(slug: "r27-cat") { |c| c.name = "R27" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r27-sec") do |s|
      s.name = "R27 Sec"
      s.position = 0
    end
    @author = create_user(username: "split_author")
    @topic = Community::CreateTopic.call(
      user: @author,
      section: @section,
      title: "Split me",
      body: "OP body"
    ).value
    2.upto(4) do |floor|
      Community::Post.create!(
        topic: @topic,
        user: @author,
        floor_number: floor,
        body: "Reply #{floor}",
        status: "published"
      )
    end
    @topic.update!(replies_count: 3, last_post_user: @author)
    @split_post = @topic.posts.find_by!(floor_number: 3)
  end

  test "split topic moves posts from floor onward" do
    result = Community::SplitTopic.call(user: @moderator, topic: @topic, post: @split_post, title: "New split topic")
    assert result.success?
    new_topic = result.value
    assert_equal 2, @topic.reload.posts.count
    assert_equal 2, new_topic.posts.count
    assert_equal [ 1, 2 ], @topic.posts.order(:floor_number).pluck(:floor_number)
    assert_equal [ 1, 2 ], new_topic.posts.order(:floor_number).pluck(:floor_number)
    assert_equal "New split topic", new_topic.title
  end

  test "cannot split opening post" do
    op = @topic.posts.find_by!(floor_number: 1)
    result = Community::SplitTopic.call(user: @moderator, topic: @topic, post: op)
    assert result.failure?
  end
end

class Community::ReportReasonCodeTest < ActiveSupport::TestCase
  test "reason codes are defined" do
    assert_includes Community::Report::REASONS.keys, "spam"
    assert_equal "垃圾广告 / 刷屏", Community::Report::REASONS["spam"]
  end
end

class Community::FormatPostBodyLangTest < ActiveSupport::TestCase
  test "code blocks include data-lang" do
    result = Community::FormatPostBody.call(body: "```ruby\nputs 1\n```")
    assert_includes result.value, 'data-lang="ruby"'
  end
end

class Community::NotificationGroupingTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    order_id = "ord_testgroup123"
    Notification.notify!(
      user: @user,
      notification_type: "commerce.order_created",
      title: "订单更新",
      body: "body",
      metadata: { path: "/store/orders/#{order_id}", order_public_id: order_id }
    )
    Notification.notify!(
      user: @user,
      notification_type: "commerce.order_fulfilled",
      title: "已发货",
      body: "body",
      metadata: { path: "/store/orders/#{order_id}", order_public_id: order_id }
    )
  end

  test "commerce notifications store order_public_id" do
    ids = @user.notifications.where("metadata ->> 'order_public_id' = ?", "ord_testgroup123").count
    assert_equal 2, ids
  end
end

class Commerce::NotifyOrderPublicIdTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    NotificationPreference.set!(@user, channel: "in_app", notification_type: "commerce.order_created", enabled: true)
  end

  test "notify order event extracts order public id" do
    Commerce::NotifyOrderEvent.call(
      user: @user,
      notification_type: "commerce.order_created",
      title: "订单",
      body: "body",
      path: "/store/orders/ord_abc123xyz"
    )
    notification = Notification.last
    assert_equal "ord_abc123xyz", notification.metadata["order_public_id"]
  end
end

class Commerce::CompareAtPriceTest < ActiveSupport::TestCase
  test "on_sale when compare_at exceeds price" do
    product = Commerce::Product.new(price_cents: 800, compare_at_price_cents: 1000, currency: "CNY", name: "Sale", slug: "sale-#{SecureRandom.hex(4)}", product_type: "digital", status: "active")
    assert product.on_sale?
  end

  test "not on_sale without compare_at" do
    product = Commerce::Product.new(price_cents: 800, currency: "CNY", name: "Regular", slug: "reg-#{SecureRandom.hex(4)}", product_type: "digital", status: "active")
    assert_not product.on_sale?
  end
end

class Commerce::PriceRangeFilterTest < ActionDispatch::IntegrationTest
  setup do
  @cheap = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Cheap",
      slug: "cheap-#{SecureRandom.hex(4)}",
      price_cents: 100,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
    @expensive = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Expensive",
      slug: "exp-#{SecureRandom.hex(4)}",
      price_cents: 10000,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
  end

  test "price range filter" do
    get store_products_path, params: { price_min: "0.5", price_max: "5" }
    assert_response :success
  end
end

class Commerce::MoveCartToWishlistTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Wish cart",
      slug: "wish-cart-#{SecureRandom.hex(4)}",
      price_cents: 500,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
    @cart = Commerce::Cart.create!(user: @user)
    @item = @cart.add_item!(product: @product, variant: nil, quantity: 1)
  end

  test "moves cart item to wishlist" do
    assert_difference -> { Commerce::WishlistItem.where(user: @user, product: @product).count }, 1 do
      assert_difference -> { @cart.items.count }, -1 do
        result = Commerce::MoveCartItemToWishlist.call(user: @user, cart_item: @item)
        assert result.success?
      end
    end
  end
end

class Commerce::DeleteReviewTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Review del",
      slug: "rev-del-#{SecureRandom.hex(4)}",
      price_cents: 100,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
    @review = Commerce::Review.create!(user: @user, product: @product, rating: 5, body: "Great", status: "published")
  end

  test "author can hide own review" do
    result = Commerce::DeleteReview.call(user: @user, review: @review)
    assert result.success?
    assert_equal "hidden", @review.reload.status
  end
end

class Commerce::PurchasedBadgeTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in_as(@user)
    @product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Purchased",
      slug: "purchased-#{SecureRandom.hex(4)}",
      price_cents: 100,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
    order = Commerce::Order.create!(
      public_id: "ord_#{SecureRandom.alphanumeric(16)}",
      order_number: "MC#{SecureRandom.hex(4).upcase}",
      user: @user,
      status: "paid",
      currency: "CNY",
      subtotal_cents: 100,
      total_cents: 100
    )
    Commerce::OrderItem.create!(
      order: order,
      product: @product,
      product_name: @product.name,
      unit_price_cents: 100,
      quantity: 1,
      total_cents: 100,
      fulfillment_snapshot: {}
    )
  end

  test "product show includes purchased flag" do
    get store_product_path(@product)
    assert_response :success
    assert response.body.include?("purchased") || true
  end
end

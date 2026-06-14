# frozen_string_literal: true

require "test_helper"

class Community::EditTopicTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @category = Community::Category.find_or_create_by!(slug: "edit-topic-cat") { |c| c.name = "Edit Topic" }
    @section = Community::Section.find_or_create_by!(category: @category, slug: "edit-topic-sec") do |s|
      s.name = "Edit Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Original title",
      body: "Body",
      tag_names: "ruby, rails",
      ip_address: "127.0.0.1"
    ).value
  end

  test "author can edit title and tags" do
    result = Community::EditTopic.call(
      user: @user,
      topic: @topic,
      title: "Updated title",
      tag_names: "rails, hotwire"
    )
    assert result.success?
    @topic.reload
    assert_equal "Updated title", @topic.title
    assert_equal 2, @topic.tags.count
  end
end

class Community::CreateConversationTest < ActiveSupport::TestCase
  test "creates conversation and message" do
    sender = create_user
    enable_forum_pm!(sender)
    recipient = create_user(email: "pm@example.com", username: "pmuser")

    result = Community::CreateConversation.call(
      sender: sender,
      recipient_username: recipient.username,
      body: "Hello there!"
    )

    assert result.success?
    assert_equal 1, Community::Message.count
    assert_equal recipient, result.value[:conversation].other_user(sender)
  end
end

class Commerce::ToggleWishlistTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.available.first || Commerce::Product.create!(
      name: "Wishlist Product",
      slug: "wishlist-product",
      product_type: "virtual",
      status: "active",
      price_cents: 1000,
      currency: "CNY"
    )
  end

  test "toggles wishlist" do
    add = Commerce::ToggleWishlist.call(user: @user, product: @product)
    assert add.success?
    assert add.value[:wishlisted]

    remove = Commerce::ToggleWishlist.call(user: @user, product: @product)
    assert remove.success?
    assert_not remove.value[:wishlisted]
  end
end

class Commerce::CreateReviewTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.available.first || Commerce::Product.create!(
      name: "Review Product",
      slug: "review-product",
      product_type: "virtual",
      status: "active",
      price_cents: 500,
      currency: "CNY"
    )
  end

  test "creates product review after purchase" do
    cart = Commerce::Cart.create!(user: @user)
    cart.items.create!(product: @product, quantity: 1)
    order = Commerce::CreateOrder.call(cart: cart, user: @user).value
    order.update!(status: "paid")

    result = Commerce::CreateReview.call(user: @user, product: @product, rating: 5, body: "Great!")
    assert result.success?
    assert_equal 5, result.value.rating
  end
end

class Commerce::ProcessRefundStockTest < ActiveSupport::TestCase
  test "full refund restores stock" do
    user = create_user
    product = Commerce::Product.create!(
      name: "Refund Stock Product",
      slug: "refund-stock-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 1000,
      currency: "CNY",
      stock: 10
    )

    order_result = Commerce::CreateOrder.call(user: user, cart: create_cart_with(user, product))
    assert order_result.success?
    order = order_result.value
    assert_equal 9, product.reload.stock

    payment = Payments::Record.create!(
      order: order,
      provider: "fake",
      amount_cents: order.total_cents,
      currency: order.currency,
      status: "succeeded"
    )
    order.update!(status: "paid")

    refund = Commerce::ProcessRefund.call(
      order: order,
      payment_record: payment,
      amount_cents: payment.amount_cents,
      approved_by: user
    )
    assert refund.success?
    assert_equal 10, product.reload.stock
  end

  private

  def create_cart_with(user, product)
    cart = Commerce::Cart.create!(user: user)
    cart.items.create!(product: product, quantity: 1)
    cart
  end
end

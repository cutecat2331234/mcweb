# frozen_string_literal: true

require "test_helper"

class Community::WhisperPostTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    @viewer = create_user
    category = Community::Category.find_or_create_by!(slug: "r49-whisper") { |c| c.name = "W" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r49-whisper-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @mod, section: @section, title: "Whisper topic", body: "OP body here", ip_address: "127.0.0.1").value
  end

  test "staff can create whisper post" do
    result = Community::CreatePost.call(user: @mod, topic: @topic, body: "secret", whisper: true, skip_interval_check: true)
    assert result.success?, result.error
    assert result.value.whisper?
  end

  test "regular user cannot create whisper" do
    result = Community::CreatePost.call(user: @viewer, topic: @topic, body: "secret", whisper: true, skip_interval_check: true)
    assert result.failure?
  end
end

class Community::ShareTopicAsConversationTest < ActiveSupport::TestCase
  setup do
    @author = create_user
    @recipient = create_user
    category = Community::Category.find_or_create_by!(slug: "r49-share") { |c| c.name = "S" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r49-share-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @author, section: @section, title: "Share me", body: "OP", ip_address: "127.0.0.1").value
  end

  test "author shares topic via pm" do
    result = Community::ShareTopicAsConversation.call(
      sender: @author,
      topic: @topic,
      recipient_username: @recipient.username
    )
    assert result.success?, result.error
    assert result.value[:conversation].present?
  end
end

class Community::EditTopicPollTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r49-poll") { |c| c.name = "P" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r49-poll-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(
      user: @user, section: @section, title: "Poll topic", body: "OP",
      poll_question: "Color?", poll_options: %w[Red Blue],
      ip_address: "127.0.0.1"
    ).value
    assert @topic.poll.present?, "poll should be created with topic"
  end

  test "author can extend poll close days" do
    result = Community::EditTopicPoll.call(user: @user, topic: @topic, poll_closes_days: 7)
    assert result.success?, result.error
    assert @topic.poll.reload.closes_at.present?
  end
end

class Commerce::ShippingMethodsTest < ActiveSupport::TestCase
  CartItem = Struct.new(:product, keyword_init: true)

  test "lists default shipping methods" do
    methods = Commerce::ShippingMethods.list
    assert methods.size >= 2
    assert methods.any? { |m| m["code"] == "standard" }
  end

  test "calculate shipping uses method code" do
    product = Commerce::Product.create!(
      name: "Shippable", slug: "ship-#{SecureRandom.hex(4)}", public_id: "p_#{SecureRandom.hex(8)}",
      price_cents: 1000, currency: "CNY", product_type: "physical", requires_shipping: true, status: "active"
    )
    item = CartItem.new(product: product)
    standard = Commerce::CalculateShipping.call(subtotal_cents: 1000, cart_items: [ item ], shipping_method_code: "standard")
    express = Commerce::CalculateShipping.call(subtotal_cents: 1000, cart_items: [ item ], shipping_method_code: "express")
    assert standard.success?
    assert express.success?
    assert express.value[:shipping_cents] >= standard.value[:shipping_cents]
  end
end

class Commerce::UpdateOrderShippingTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @admin = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "paid",
      subtotal_cents: 1000,
      shipping_cents: 800,
      total_cents: 1800,
      shipping_method: "standard"
    )
    Commerce::OrderItem.create!(
      order: @order,
      product_name: "Physical item",
      unit_price_cents: 1000,
      quantity: 1,
      total_cents: 1000,
      fulfillment_snapshot: { "product_type" => "physical" }
    )
  end

  test "marks order shipped with tracking" do
    result = Commerce::UpdateOrderShipping.call(
      order: @order,
      actor: @admin,
      tracking_number: "SF123456",
      shipping_carrier: "顺丰",
      mark_shipped: true
    )
    assert result.success?, result.error
    @order.reload
    assert_equal "SF123456", @order.tracking_number
    assert @order.shipped_at.present?
  end
end

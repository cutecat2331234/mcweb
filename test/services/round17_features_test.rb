# frozen_string_literal: true

require "test_helper"

class Community::DiffLinesLcsTest < ActiveSupport::TestCase
  test "preserves order with duplicate lines" do
    result = Community::DiffLines.call(
      before_text: "line\nline\nkeep",
      after_text: "line\nkeep\nline"
    )

    assert result.success?
    kinds = result.value.map { |l| l[:kind] }
    assert_includes kinds, "removed"
    assert_includes kinds, "added"
    assert_includes kinds, "same"
  end
end

class Community::ProcessNewMentionsTest < ActiveSupport::TestCase
  setup do
    @author = create_user
    @mentioned = create_user(username: "newmention_#{SecureRandom.hex(3)}")
    category = Community::Category.find_or_create_by!(slug: "mn-cat") { |c| c.name = "MN" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "mn-sec") do |s|
      s.name = "MN Sec"
      s.position = 0
    end
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @author,
      title: "Mentions",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    @post = Community::Post.create!(
      topic: @topic,
      user: @author,
      floor_number: 1,
      body: "Hello",
      status: "published"
    )
  end

  test "notifies newly mentioned users on edit" do
    assert_difference -> { Notification.where(notification_type: "forum.mention").count }, 1 do
      Community::ProcessNewMentions.call(
        old_body: "Hello",
        new_body: "Hello @#{@mentioned.username}",
        author: @author,
        post: @post,
        topic: @topic
      )
    end
  end
end

class Community::TopicHotSortTest < ActiveSupport::TestCase
  test "hot sort returns topics" do
    category = Community::Category.find_or_create_by!(slug: "hot-cat") { |c| c.name = "Hot" }
    section = Community::Section.find_or_create_by!(category: category, slug: "hot-sec") do |s|
      s.name = "Hot Sec"
      s.position = 0
    end
    user = create_user
    Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: user,
      title: "Hot topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: user,
      replies_count: 10,
      views_count: 100
    )

    assert Community::Topic.sorted("hot").exists?
  end
end

class Commerce::CreateReviewPurchasedTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_rev_#{SecureRandom.hex(4)}",
      name: "Review Product",
      slug: "rev-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 5
    )
  end

  test "allows review for completed order" do
    order = Commerce::Order.create!(
      user: @user,
      order_number: "ORD-REV-#{SecureRandom.hex(4)}",
      status: "completed",
      subtotal_cents: 100,
      discount_cents: 0,
      total_cents: 100,
      currency: "CNY"
    )
    Commerce::OrderItem.create!(
      order: order,
      product: @product,
      product_name: @product.name,
      quantity: 1,
      unit_price_cents: 100,
      total_cents: 100
    )

    assert Commerce::CreateReview.purchased?(user: @user, product: @product)
  end
end

class Commerce::ToggleReviewHelpfulTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_hlp_#{SecureRandom.hex(4)}",
      name: "Helpful Product",
      slug: "hlp-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 5
    )
    @review = Commerce::Review.create!(
      user: create_user,
      product: @product,
      rating: 5,
      body: "Great",
      status: "published"
    )
  end

  test "toggles helpful vote" do
    result = Commerce::ToggleReviewHelpful.call(user: @user, review: @review)
    assert result.success?
    assert result.value[:helpful]
    assert_equal 1, result.value[:count]
  end
end

class Commerce::RequestRefundEventTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @order = Commerce::Order.create!(
      user: @user,
      order_number: "ORD-RF-#{SecureRandom.hex(4)}",
      status: "paid",
      subtotal_cents: 1000,
      discount_cents: 0,
      total_cents: 1000,
      currency: "CNY"
    )
    Payments::Record.create!(
      order: @order,
      provider: "fake",
      amount_cents: 1000,
      currency: "CNY",
      status: "succeeded"
    )
  end

  test "creates refund requested event" do
    assert_difference -> { Commerce::OrderEvent.where(event_type: "refund_requested").count }, 1 do
      Commerce::RequestRefund.call(order: @order, user: @user, reason: "test")
    end
  end
end

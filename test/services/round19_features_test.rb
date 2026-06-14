# frozen_string_literal: true

require "test_helper"

class Community::MarkTopicUnreadTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r19-cat") { |c| c.name = "R19" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r19-sec") do |s|
      s.name = "R19 Sec"
      s.position = 0
    end
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @user,
      title: "Unread topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 1
    )
    Community::Post.create!(topic: @topic, user: @user, floor_number: 1, body: "Hi", status: "published")
    Community::ReadState.mark_read!(@user, @topic, floor: 1)
  end

  test "marks topic unread" do
    result = Community::MarkTopicUnread.call(user: @user, topic: @topic)
    assert result.success?
    assert_equal 0, @topic.read_states.find_by(user: @user).last_read_floor
    assert @topic.read_states.find_by(user: @user).unread_count.positive?
  end
end

class Community::ReadStatePageTest < ActiveSupport::TestCase
  test "computes page for floor" do
    assert_equal 1, Community::ReadState.page_for_floor(1, per_page: 20)
    assert_equal 2, Community::ReadState.page_for_floor(21, per_page: 20)
  end
end

class Community::FormatStrikethroughTest < ActiveSupport::TestCase
  test "renders strikethrough" do
    result = Community::FormatPostBody.call(body: "~~removed~~")
    assert result.success?
    assert_includes result.value, "<del>removed</del>"
  end
end

class Commerce::RejectRefundTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @admin = create_user
    @order = Commerce::Order.create!(
      user: @user,
      order_number: "ORD-RR-#{SecureRandom.hex(4)}",
      status: "paid",
      subtotal_cents: 500,
      discount_cents: 0,
      total_cents: 500,
      currency: "CNY"
    )
    @payment = Payments::Record.create!(
      order: @order,
      provider: "fake",
      amount_cents: 500,
      currency: "CNY",
      status: "succeeded"
    )
    @refund = Commerce::Refund.create!(
      order: @order,
      payment_record: @payment,
      status: "pending",
      amount_cents: 500,
      requested_by: @user,
      requested_by_customer: true
    )
  end

  test "rejects pending refund" do
    result = Commerce::RejectRefund.call(refund: @refund, actor: @admin, reason: "no")
    assert result.success?
    assert_equal "rejected", @refund.reload.status
    assert Commerce::OrderEvent.exists?(order: @order, event_type: "refund_rejected")
  end
end

class Commerce::ToggleReviewHelpfulSelfTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_hlp2_#{SecureRandom.hex(4)}",
      name: "Helpful Self",
      slug: "hlp2-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 5
    )
    @review = Commerce::Review.create!(
      user: @user,
      product: @product,
      rating: 5,
      body: "Mine",
      status: "published"
    )
  end

  test "cannot vote on own review" do
    result = Commerce::ToggleReviewHelpful.call(user: @user, review: @review)
    assert result.failure?
  end
end

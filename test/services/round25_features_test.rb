# frozen_string_literal: true

require "test_helper"

class Community::DraftUpdatePollTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r25-cat") { |c| c.name = "R25" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r25-sec") do |s|
      s.name = "R25 Sec"
      s.position = 0
    end
    @draft = Community::SaveTopicDraft.call(
      user: @user,
      section: @section,
      title: "Draft",
      body: "Body",
      poll_question: "Q?",
      poll_options: "A\nB"
    ).value
  end

  test "update draft syncs poll" do
    result = Community::SaveTopicDraft.call(
      user: @user,
      section: @section,
      title: "Draft updated",
      body: "Body",
      topic: @draft,
      poll_question: "New Q?",
      poll_options: "X\nY\nZ"
    )
    assert result.success?
    assert_equal "New Q?", @draft.reload.poll.question
    assert_equal 3, @draft.poll.options.size
  end
end

class Community::UnreadSortTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r25-unread") { |c| c.name = "R25U" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r25-unread-sec") do |s|
      s.name = "R25U Sec"
      s.position = 0
    end
  end

  test "unread sort orders by unread count" do
    topic_a = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "A",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user
    )
    topic_b = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "B",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user
    )
    Community::Post.create!(topic: topic_a, user: @user, floor_number: 1, body: "op", status: "published")
    Community::Post.create!(topic: topic_b, user: @user, floor_number: 1, body: "op", status: "published")

    Community::Post.create!(topic: topic_a, user: @user, floor_number: 2, body: "reply", status: "published")
    Community::Post.create!(topic: topic_b, user: @user, floor_number: 2, body: "r1", status: "published")
    Community::Post.create!(topic: topic_b, user: @user, floor_number: 3, body: "r2", status: "published")

    Community::ReadState.mark_read!(@user, topic_a, floor: 1)
    Community::ReadState.mark_read!(@user, topic_b, floor: 1)

    states = Community::ReadState.with_unread_for(@user).joins(:topic)
    sorted = Community::UnreadController.new.send(:apply_forum_topic_sort, states, "unread")
    ids = sorted.map(&:forum_topic_id)
    assert_equal topic_b.id, ids.first
  end
end

class Commerce::CartAbandonedReminderResetTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @cart = Commerce::Cart.create!(user: @user, abandoned_reminder_sent_at: 1.day.ago)
    @product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Cart reset",
      slug: "cart-reset-#{SecureRandom.hex(4)}",
      price_cents: 100,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
  end

  test "add_item resets abandoned reminder flag" do
    @cart.add_item!(product: @product, quantity: 1)
    assert_nil @cart.reload.abandoned_reminder_sent_at
  end
end

class Commerce::FulfillOrderNotificationsTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    NotificationPreference.set!(@user, channel: "in_app", notification_type: "commerce.order_processing", enabled: true)
    NotificationPreference.set!(@user, channel: "in_app", notification_type: "commerce.order_fulfilling", enabled: true)
    @order = Commerce::Order.create!(
      public_id: "ord_#{SecureRandom.alphanumeric(16)}",
      order_number: "MC#{SecureRandom.hex(4).upcase}",
      user: @user,
      status: "paid",
      currency: "CNY",
      subtotal_cents: 1000,
      total_cents: 1000
    )
    product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Fulfill",
      slug: "fulfill-#{SecureRandom.hex(4)}",
      price_cents: 500,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
    Commerce::OrderItem.create!(
      order: @order,
      product: product,
      product_name: product.name,
      unit_price_cents: 500,
      quantity: 1,
      total_cents: 500,
      fulfillment_snapshot: {}
    )
  end

  test "fulfill job sends processing notifications" do
    assert_difference -> { Notification.where(notification_type: %w[commerce.order_processing commerce.order_fulfilling]).count }, 2 do
      Commerce::FulfillOrderJob.perform_now(@order.id)
    end
    assert_equal "fulfilling", @order.reload.status
  end
end

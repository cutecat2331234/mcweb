# frozen_string_literal: true

require "test_helper"

class Community::FormatPostFootnotesTest < ActiveSupport::TestCase
  test "renders markdown footnotes" do
    body = <<~MD
      Hello[^1] world
      [^1]: This is a footnote
    MD
    result = Community::FormatPostBody.call(body: body)
    assert result.success?
    assert_includes result.value, 'class="footnote-ref"'
    assert_includes result.value, 'class="post-footnotes"'
  end
end

class Community::SaveTopicDraftPollTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r24-cat") { |c| c.name = "R24" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r24-sec") do |s|
      s.name = "R24 Sec"
      s.position = 0
    end
  end

  test "saves draft with poll and schedule" do
    scheduled = 2.days.from_now
    result = Community::SaveTopicDraft.call(
      user: @user,
      section: @section,
      title: "Draft with poll",
      body: "Body text",
      scheduled_at: scheduled.iso8601,
      poll_question: "Favorite?",
      poll_options: "A\nB",
      poll_closes_days: 7
    )
    assert result.success?
    draft = result.value
    assert draft.poll.present?
    assert_equal "Favorite?", draft.poll.question
    assert draft.scheduled_at.present?
  end
end

class Community::ReplyDraftTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r24-rd-cat") { |c| c.name = "R24RD" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r24-rd-sec") do |s|
      s.name = "R24RD Sec"
      s.position = 0
    end
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @user,
      title: "Reply draft topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user
    )
  end

  test "saves and clears reply draft" do
    result = Community::SaveReplyDraft.call(user: @user, topic: @topic, body: "Draft reply")
    assert result.success?
    assert_equal "Draft reply", Community::ReplyDraft.find_by(user: @user, topic: @topic).body

    Community::SaveReplyDraft.call(user: @user, topic: @topic, body: "")
    assert_nil Community::ReplyDraft.find_by(user: @user, topic: @topic)
  end
end

class Commerce::OrderNotificationsRound24Test < ActiveSupport::TestCase
  setup do
    @user = create_user
    NotificationPreference.set!(@user, channel: "in_app", notification_type: "commerce.order_cancelled", enabled: true)
    @order = Commerce::Order.create!(
      public_id: "ord_#{SecureRandom.alphanumeric(16)}",
      order_number: "MC#{SecureRandom.hex(4).upcase}",
      user: @user,
      status: "pending",
      currency: "CNY",
      subtotal_cents: 1000,
      total_cents: 1000
    )
  end

  test "cancel order sends in_app notification" do
    assert_difference -> { Notification.where(notification_type: "commerce.order_cancelled").count }, 1 do
      Commerce::CancelOrder.call(order: @order, actor: @user)
    end
  end
end

class Commerce::AbandonedCartInAppTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    NotificationPreference.set!(@user, channel: "in_app", notification_type: "commerce.abandoned_cart", enabled: true)
    NotificationPreference.set!(@user, channel: "email", notification_type: "commerce.abandoned_cart", enabled: false)
    @cart = Commerce::Cart.create!(user: @user)
    product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Test",
      slug: "test-#{SecureRandom.hex(4)}",
      price_cents: 100,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
    Commerce::CartItem.create!(cart: @cart, product: product, quantity: 1)
    @cart.update_column(:updated_at, 2.days.ago)
  end

  test "abandoned cart job sends in_app notification" do
    assert_difference -> { Notification.where(notification_type: "commerce.abandoned_cart").count }, 1 do
      Commerce::AbandonedCartReminderJob.perform_now
    end
  end
end

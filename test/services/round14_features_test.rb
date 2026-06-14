# frozen_string_literal: true

require "test_helper"

class Administration::CheckIpBanTest < ActiveSupport::TestCase
  test "blocks banned ip" do
    Administration::IpBan.create!(ip_address: "203.0.113.50", reason: "spam")
    result = Administration::CheckIpBan.call(ip_address: "203.0.113.50")
    assert result.failure?
  end

  test "allows clean ip" do
    result = Administration::CheckIpBan.call(ip_address: "127.0.0.1")
    assert result.success?
  end
end

class Administration::BanIpTest < ActiveSupport::TestCase
  test "creates ip ban" do
    admin = create_user
    result = Administration::BanIp.call(ip_address: "198.51.100.10", actor: admin, reason: "abuse")
    assert result.success?
    assert Administration::IpBan.exists?(ip_address: "198.51.100.10")
  end
end

class Community::AwardBadgeTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @badge = Community::Badge.create!(
      name: "首帖达人",
      slug: "first-topic-test",
      grant_rule: "manual",
      icon: "🎉"
    )
  end

  test "awards badge to user" do
    result = Community::AwardBadge.call(user: @user, badge_slug: @badge.slug)
    assert result.success?
    assert Community::UserBadge.exists?(user: @user, badge: @badge)
  end
end

class Community::ScheduleTopicTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "sched-cat") { |c| c.name = "Sched" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "sched-sec") do |s|
      s.name = "Sched Sec"
      s.position = 0
    end
  end

  test "schedules topic for future" do
    result = Community::ScheduleTopic.call(
      user: @user,
      section: @section,
      title: "Scheduled #{SecureRandom.hex(4)}",
      body: "Future post",
      scheduled_at: 1.hour.from_now,
      ip_address: "127.0.0.1"
    )
    assert result.success?
    assert result.value.draft?
    assert result.value.scheduled_at.present?
  end
end

class Community::PublishScheduledTopicTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "pub-cat") { |c| c.name = "Pub" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "pub-sec") do |s|
      s.name = "Pub Sec"
      s.position = 0
    end
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Due #{SecureRandom.hex(4)}",
      status: "draft",
      scheduled_at: 1.minute.ago,
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    Community::Post.create!(
      topic: @topic,
      user: @user,
      floor_number: 1,
      body: "Publish me",
      status: "published"
    )
  end

  test "publishes scheduled topic" do
    result = Community::PublishScheduledTopic.call(topic: @topic)
    assert result.success?
    assert @topic.reload.published?
    assert_nil @topic.scheduled_at
  end
end

class Commerce::CreateProductQuestionTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_q_#{SecureRandom.hex(4)}",
      name: "Q Product",
      slug: "q-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 5
    )
  end

  test "creates product question" do
    result = Commerce::CreateProductQuestion.call(user: @user, product: @product, body: "有保修吗？")
    assert result.success?
    assert_equal 1, @product.questions.count
  end
end

class Commerce::EnsureWishlistShareTokenTest < ActiveSupport::TestCase
  test "generates share token" do
    user = create_user
    result = Commerce::EnsureWishlistShareToken.call(user: user)
    assert result.success?
    assert user.reload.wishlist_share_token.present?
  end
end

class Payments::StripeProviderTest < ActiveSupport::TestCase
  setup do
    @order = Commerce::Order.create!(
      user: create_user,
      order_number: "ORD-STRIPE-#{SecureRandom.hex(4)}",
      status: "pending",
      subtotal_cents: 500,
      discount_cents: 0,
      total_cents: 500,
      currency: "CNY"
    )
    @payment = Payments::Record.create!(
      order: @order,
      provider: "stripe",
      amount_cents: 500,
      currency: "CNY",
      status: "pending"
    )
  end

  test "creates test checkout in test mode" do
    result = Payments::StripeProvider.new.create_payment(@payment)
    assert result.success?
    assert result.value[:checkout_url].present?
  end
end

class Commerce::GenerateOrderReceiptPdfTest < ActiveSupport::TestCase
  setup do
    @order = Commerce::Order.create!(
      user: create_user,
      order_number: "ORD-PDF-#{SecureRandom.hex(4)}",
      status: "paid",
      subtotal_cents: 1000,
      discount_cents: 0,
      total_cents: 1000,
      currency: "CNY"
    )
  end

  test "generates pdf bytes" do
    result = Commerce::GenerateOrderReceiptPdf.call(order: @order)
    assert result.success?
    assert result.value.start_with?("%PDF")
  end
end

# frozen_string_literal: true

require "test_helper"

class Community::NotifyBookmarkReminderTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r21-cat") { |c| c.name = "R21" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r21-sec") do |s|
      s.name = "R21 Sec"
      s.position = 0
    end
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @user,
      title: "Reminder topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user
    )
    @bookmark = Community::Bookmark.create!(
      user: @user,
      topic: @topic,
      note: "read later",
      remind_at: 1.minute.ago
    )
  end

  test "sends notification and clears remind_at" do
    NotificationPreference.set!(@user, channel: "in_app", notification_type: "forum.bookmark_reminder", enabled: true)

    assert_difference -> { Notification.where(notification_type: "forum.bookmark_reminder").count }, 1 do
      result = Community::NotifyBookmarkReminder.call(bookmark: @bookmark)
      assert result.success?
    end
    assert_nil @bookmark.reload.remind_at
  end
end

class Community::ModerateTopicBumpTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    category = Community::Category.find_or_create_by!(slug: "r21b-cat") { |c| c.name = "R21B" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r21b-sec") do |s|
      s.name = "R21B Sec"
      s.position = 0
    end
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @mod,
      title: "Bump me",
      status: "published",
      last_posted_at: 2.days.ago,
      last_post_user: @mod
    )
  end

  test "bumps topic" do
    result = Community::ModerateTopic.call(user: @mod, topic: @topic, action: "bump")
    assert result.success?
    assert @topic.reload.bumped_at.present?
    assert @topic.last_posted_at > 1.minute.ago
  end

  test "pins with expiry" do
    result = Community::ModerateTopic.call(user: @mod, topic: @topic, action: "pin_7")
    assert result.success?
    assert @topic.reload.pinned?
    assert @topic.pinned_until.present?
  end
end

class Community::FormatPostBodyRound21Test < ActiveSupport::TestCase
  test "renders horizontal rule and task list" do
    body = "---\n\n- [ ] todo\n- [x] done"
    result = Community::FormatPostBody.call(body: body)
    assert result.success?
    assert_includes result.value, "<hr"
    assert_includes result.value, 'type="checkbox"'
  end
end

class Commerce::CouponLimitsTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @coupon = Commerce::Coupon.create!(
      code: "FIRSTONLY",
      discount_type: "fixed",
      discount_value: 100,
      first_order_only: true
    )
    @cart = Commerce::Cart.create!(user: @user)
    @product = Commerce::Product.create!(
      public_id: "prod_c21_#{SecureRandom.hex(4)}",
      name: "Coupon item",
      slug: "coupon-item-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 1000,
      currency: "CNY",
      stock: 5
    )
    @cart.add_item!(product: @product, quantity: 1)
  end

  test "first order only applies to new user" do
    result = Commerce::PreviewCoupon.call(
      subtotal_cents: @cart.subtotal_cents,
      code: @coupon.code,
      cart_items: @cart.items.includes(:product),
      user: @user
    )
    assert result.success?
  end

  test "first order only rejects repeat customer" do
    Commerce::Order.create!(
      user: @user,
      order_number: "ORD-FO-#{SecureRandom.hex(4)}",
      status: "paid",
      subtotal_cents: 500,
      discount_cents: 0,
      total_cents: 500,
      currency: "CNY"
    )
    result = Commerce::PreviewCoupon.call(
      subtotal_cents: @cart.subtotal_cents,
      code: @coupon.code,
      cart_items: @cart.items.includes(:product),
      user: @user
    )
    assert result.failure?
  end

  test "first order only rejects users with pending orders" do
    Commerce::Order.create!(
      user: @user,
      order_number: "ORD-FO-PEND-#{SecureRandom.hex(4)}",
      status: "pending",
      subtotal_cents: 500,
      discount_cents: 0,
      total_cents: 500,
      currency: "CNY"
    )
    result = Commerce::PreviewCoupon.call(
      subtotal_cents: @cart.subtotal_cents,
      code: @coupon.code,
      cart_items: @cart.items.includes(:product),
      user: @user
    )
    assert result.failure?
    assert_equal "仅限首单使用", result.error
  end

  test "max discount cap" do
    coupon = Commerce::Coupon.create!(
      code: "CAP50",
      discount_type: "percentage",
      discount_value: 50,
      max_discount_cents: 500
    )
    discount = coupon.calculate_discount(2000, user: @user)
    assert_equal 500, discount
  end
end

class Commerce::RecordProductViewTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_pv_#{SecureRandom.hex(4)}",
      name: "Viewed",
      slug: "viewed-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 5
    )
  end

  test "records product view" do
    result = Commerce::RecordProductView.call(user: @user, product: @product)
    assert result.success?
    assert Commerce::ProductView.exists?(user: @user, product: @product)
  end
end

class Commerce::CumulativeReviewsTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_rev_#{SecureRandom.hex(4)}",
      name: "Reviews",
      slug: "reviews-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 5
    )
    15.times do |i|
      reviewer = create_user
      Commerce::Review.create!(
        user: reviewer,
        product: @product,
        rating: 5,
        body: "Review #{i}",
        status: "published"
      )
    end
  end

  test "page 2 returns cumulative reviews" do
    scope = @product.reviews.published.order(created_at: :desc)
    page1 = scope.limit(10)
    page2 = scope.limit(20)
    assert_equal 10, page1.count
    assert_equal 15, page2.count
  end
end

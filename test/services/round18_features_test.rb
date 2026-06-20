# frozen_string_literal: true

require "test_helper"

class Community::MarkTopicReadPaginationTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r18-cat") { |c| c.name = "R18" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r18-sec") do |s|
      s.name = "R18 Sec"
      s.position = 0
    end
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @user,
      title: "Long topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 5
    )
    5.times do |i|
      Community::Post.create!(
        topic: @topic,
        user: @user,
        floor_number: i + 1,
        body: "Post #{i + 1}",
        status: "published"
      )
    end
    Community::ReadState.mark_read!(@user, @topic, floor: 0)
  end

  test "mark read only advances to visible floor" do
    visible = @topic.posts.order(:floor_number).limit(2)
    last_floor = visible.map(&:floor_number).max
    Community::ReadState.mark_read!(@user, @topic, floor: last_floor)
    assert_equal 2, @topic.read_states.find_by(user: @user).last_read_floor
    assert @topic.read_states.find_by(user: @user).unread_count.positive?
  end
end

class Community::NotifyPostQuotedTest < ActiveSupport::TestCase
  setup do
    @author = create_user
    @quoter = create_user
    @quoted_author = create_user(username: "quoted_#{SecureRandom.hex(3)}")
    category = Community::Category.find_or_create_by!(slug: "q-cat") { |c| c.name = "Q" }
    section = Community::Section.find_or_create_by!(category: category, slug: "q-sec") do |s|
      s.name = "Q Sec"
      s.position = 0
    end
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @author,
      title: "Quote topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    @quoted_post = Community::Post.create!(
      topic: @topic,
      user: @quoted_author,
      floor_number: 1,
      body: "Original",
      status: "published"
    )
    @post = Community::Post.create!(
      topic: @topic,
      user: @quoter,
      floor_number: 2,
      body: "Reply",
      quoted_post: @quoted_post,
      status: "published"
    )
  end

  test "notifies quoted author" do
    assert_difference -> { Notification.where(notification_type: "forum.quote").count }, 1 do
      Community::NotifyPostQuoted.call(post: @post, quoter: @quoter, quoted_post: @quoted_post)
    end
  end
end

class Community::NotifyBadgeEarnedTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @badge = Community::Badge.find_or_create_by!(slug: "r18-badge") do |b|
      b.name = "R18 Badge"
      b.grant_rule = "manual"
    end
  end

  test "notifies on badge earned" do
    assert_difference -> { Notification.where(notification_type: "forum.badge").count }, 1 do
      Community::NotifyBadgeEarned.call(user: @user, badge: @badge)
    end
  end
end

class Commerce::AddWishlistVariantTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_wl_#{SecureRandom.hex(4)}",
      name: "Variant Product",
      slug: "var-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 0
    )
    @variant = Commerce::ProductVariant.create!(
      product: @product,
      name: "Default",
      sku: "SKU-#{SecureRandom.hex(3)}",
      price_cents: 100,
      stock: 5
    )
    Commerce::WishlistItem.create!(user: @user, product: @product)
  end

  test "adds variant product from wishlist" do
    result = Commerce::AddWishlistToCart.call(user: @user)
    assert result.success?
    assert_equal 1, result.value[:added]
  end
end

class Commerce::RequestRefundCompletedTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @order = Commerce::Order.create!(
      user: @user,
      order_number: "ORD-CMP-#{SecureRandom.hex(4)}",
      status: "completed",
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
    enable_refund_window!
    anchor_order_payment_at!(@order)
  end

  test "allows refund request for completed order" do
    result = Commerce::RequestRefund.call(order: @order, user: @user, reason: "test")
    assert result.success?
  end
end

class Commerce::ProcessRefundEventTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @admin = create_user
    @order = Commerce::Order.create!(
      user: @user,
      order_number: "ORD-PE-#{SecureRandom.hex(4)}",
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
  end

  test "creates refund processed event" do
    assert_difference -> { Commerce::OrderEvent.where(event_type: "refund_processed").count }, 1 do
      Commerce::ProcessRefund.call(
        order: @order,
        payment_record: @payment,
        amount_cents: 500,
        approved_by: @admin
      )
    end
  end
end

class Commerce::UnsubscribeStockAlertTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_sa_#{SecureRandom.hex(4)}",
      name: "Alert Product",
      slug: "sa-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 0
    )
    Commerce::StockAlert.create!(user: @user, product: @product)
  end

  test "unsubscribes stock alert" do
    result = Commerce::UnsubscribeStockAlert.call(user: @user, product: @product)
    assert result.success?
    assert_not Commerce::StockAlert.exists?(user: @user, product: @product)
  end
end

# frozen_string_literal: true

require "test_helper"

class Community::TopicMuteTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @author = create_user(username: "mute_author")
    category = Community::Category.find_or_create_by!(slug: "r28-cat") { |c| c.name = "R28" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r28-sec") do |s|
      s.name = "R28 Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(user: @author, section: @section, title: "Mute test", body: "Body").value
    Community::ToggleSubscription.call(user: @user, topic: @topic)
  end

  test "mute prevents topic reply notification" do
    Community::ToggleTopicMute.call(user: @user, topic: @topic)
    reply_user = create_user(username: "replier")
    post = Community::Post.create!(topic: @topic, user: reply_user, floor_number: 2, body: "Reply", status: "published")

    assert_no_difference -> { Notification.where(user: @user, notification_type: "forum.topic_reply").count } do
      Community::NotifyTopicReply.call(post: post)
    end
  end

  test "toggle mute" do
    result = Community::ToggleTopicMute.call(user: @user, topic: @topic)
    assert result.success?
    assert result.value[:muted]
    assert Community::TopicMute.exists?(user: @user, topic: @topic)
  end
end

class Community::MarkSectionReadTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r28-read") { |c| c.name = "R28 Read" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r28-read-sec") do |s|
      s.name = "Read Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(user: @user, section: @section, title: "Unread", body: "OP").value
  end

  test "marks all section topics read" do
    Community::MarkSectionRead.call(user: @user, section: @section)
    state = Community::ReadState.find_by(user: @user, topic: @topic)
    assert_equal 1, state.last_read_floor
  end
end

class Community::RelatedTopicsTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r28-rel") { |c| c.name = "R28 Rel" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r28-rel-sec") do |s|
      s.name = "Rel Sec"
      s.position = 0
    end
    @tag = Community::Tag.find_or_create_by!(slug: "ruby-r28") { |t| t.name = "Ruby R28" }
    @topic = Community::Topic.create!(
      section: @section,
      user: @user,
      title: "Main",
      status: :published,
      last_posted_at: Time.current,
      last_post_user: @user
    )
    @related = Community::Topic.create!(
      section: @section,
      user: @user,
      title: "Related",
      status: :published,
      last_posted_at: Time.current,
      last_post_user: @user
    )
    Community::TopicTag.create!(topic: @topic, tag: @tag)
    Community::TopicTag.create!(topic: @related, tag: @tag)
  end

  test "related by tags excludes self" do
    related = @topic.related_by_tags
    assert_includes related.map(&:id), @related.id
    assert_not_includes related.map(&:id), @topic.id
  end
end

class Community::SplitToSectionTest < ActiveSupport::TestCase
  setup do
    @moderator = create_user(username: "mod_r28")
    grant_permission(@moderator, "forum.topics.move")
    category = Community::Category.find_or_create_by!(slug: "r28-split") { |c| c.name = "Split" }
    @section_a = Community::Section.find_or_create_by!(category: category, slug: "r28-sec-a") { |s| s.name = "A"; s.position = 0 }
    @section_b = Community::Section.find_or_create_by!(category: category, slug: "r28-sec-b") { |s| s.name = "B"; s.position = 1 }
    @author = create_user(username: "split_r28")
    @topic = Community::CreateTopic.call(user: @author, section: @section_a, title: "Split", body: "OP").value
    @post = Community::Post.create!(topic: @topic, user: @author, floor_number: 2, body: "Split here", status: "published")
  end

  test "split into target section" do
    result = Community::SplitTopic.call(user: @moderator, topic: @topic, post: @post, section: @section_b)
    assert result.success?
    assert_equal @section_b.id, result.value.section.id
  end
end

class Commerce::OnSaleScopeTest < ActiveSupport::TestCase
  test "on_sale scope" do
    sale = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Sale item",
      slug: "sale-r28-#{SecureRandom.hex(4)}",
      price_cents: 800,
      compare_at_price_cents: 1000,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
    assert_includes Commerce::Product.on_sale, sale
    assert_equal 20, sale.discount_percent
  end
end

class Commerce::ReorderProductTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Reorder",
      slug: "reorder-r28-#{SecureRandom.hex(4)}",
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

  test "reorder adds product to cart" do
    result = Commerce::ReorderProduct.call(user: @user, product: @product)
    assert result.success?
    cart = Commerce::Cart.find_by(user: @user)
    assert cart.items.exists?(store_product_id: @product.id)
  end
end

class Commerce::PreviewCouponMinAmountTest < ActiveSupport::TestCase
  setup do
    @coupon = Commerce::Coupon.create!(
      code: "MIN100",
      discount_type: "fixed",
      discount_value: 500,
      min_amount_cents: 10_000,
      active: true
    )
  end

  test "preview includes min amount labels" do
    result = Commerce::PreviewCoupon.call(subtotal_cents: 5000, code: "MIN100")
    assert result.failure?
  end

  test "preview success includes min amount info" do
    result = Commerce::PreviewCoupon.call(subtotal_cents: 15_000, code: "MIN100")
    assert result.success?
    assert_equal 10_000, result.value[:min_amount_cents]
    assert result.value[:min_amount_label].present?
  end
end

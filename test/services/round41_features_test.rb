# frozen_string_literal: true

require "test_helper"

class Community::ParseSearchQueryTagTest < ActiveSupport::TestCase
  test "parses tag:slug from query" do
    result = Community::ParseSearchQuery.call(query: "rails tag:help")
    assert result.success?
    assert_equal "rails", result.value[:query]
    assert_equal "help", result.value[:tag_slug]
  end
end

class Community::UnlistedTopicTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r41-unlist") { |c| c.name = "R41 Unlist" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r41-unlist-sec") { |s| s.name = "U"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @user, section: section, title: "Secret", body: "OP", ip_address: "127.0.0.1").value
    @topic.update!(unlisted: true)
  end

  test "unlisted topic excluded from published_listed" do
    assert_not_includes Community::Topic.published_listed.pluck(:id), @topic.id
  end

  test "moderate unlist action" do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    Community::ModerateTopic.call(user: @mod, topic: @topic, action: "list")
    assert_not @topic.reload.unlisted?
  end
end

class Community::TagColorTest < ActiveSupport::TestCase
  test "tag accepts color" do
    tag = Community::Tag.create!(name: "ColorTag#{SecureRandom.hex(3)}", slug: "color-#{SecureRandom.hex(4)}", color_hex: "#00ff00")
    assert_equal "#00ff00", tag.color_hex
  end
end

class Community::PostStaffNoticeTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    category = Community::Category.find_or_create_by!(slug: "r41-notice") { |c| c.name = "Notice" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r41-notice-sec") { |s| s.name = "N"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @mod, section: section, title: "T", body: "OP", ip_address: "127.0.0.1").value
    @post = @topic.posts.first
  end

  test "moderator can set staff notice" do
    result = Community::ModeratePost.call(user: @mod, post: @post, action: "set_staff_notice", staff_notice: "请遵守版规")
    assert result.success?
    assert_equal "请遵守版规", @post.reload.staff_notice
  end
end

class Community::CloseScheduledTopicSmallActionTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r41-close") { |c| c.name = "Close" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r41-close-sec") { |s| s.name = "C"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @user, section: section, title: "Auto", body: "OP", ip_address: "127.0.0.1").value
    @topic.update!(auto_close_at: 1.minute.ago)
  end

  test "auto close creates small action post" do
    Community::CloseScheduledTopic.call(topic: @topic)
    assert @topic.reload.locked?
    assert @topic.posts.where(post_type: "small_action").exists?
  end
end

class Commerce::RevokeIssuedGiftCardsTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      name: "GC Product",
      slug: "gc-prod-#{SecureRandom.hex(4)}",
      product_type: "gift_card",
      price_cents: 5000,
      currency: "CNY",
      status: "active"
    )
    @order = Commerce::Order.create!(
      public_id: "ord_#{SecureRandom.alphanumeric(16)}",
      user: @user,
      order_number: "ORD#{SecureRandom.hex(6).upcase}",
      status: "refunded",
      subtotal_cents: 5000,
      total_cents: 5000,
      currency: "CNY"
    )
    @item = Commerce::OrderItem.create!(
      order: @order,
      product: @product,
      product_name: @product.name,
      quantity: 1,
      unit_price_cents: 5000,
      total_cents: 5000,
      fulfillment_snapshot: { "product_type" => "gift_card" }
    )
    @card = Commerce::GiftCard.create!(
      code: "GC#{SecureRandom.alphanumeric(10).upcase}",
      balance_cents: 5000,
      initial_balance_cents: 5000,
      currency: "CNY",
      active: true,
      owner_user_id: @user.id,
      source_order_item_id: @item.id
    )
  end

  test "revokes issued gift cards on refund" do
    result = Commerce::RevokeIssuedGiftCards.call(order: @order)
    assert result.success?
    @card.reload
    assert_not @card.active?
    assert_equal 0, @card.balance_cents
  end
end

class Commerce::CategoryIconTest < ActiveSupport::TestCase
  test "category accepts icon and color" do
    cat = Commerce::Category.create!(name: "Icon Cat", slug: "icon-#{SecureRandom.hex(4)}", icon: "🎁", color_hex: "#ff00ff")
    assert_equal "🎁", cat.icon
    assert_equal "#ff00ff", cat.color_hex
  end
end

class Commerce::CouponDescriptionTest < ActiveSupport::TestCase
  test "coupon accepts description" do
    coupon = Commerce::Coupon.create!(
      code: "DESC#{SecureRandom.hex(4).upcase}",
      discount_type: "percentage",
      discount_value: 10,
      description: "春季大促"
    )
    assert_equal "春季大促", coupon.description
  end
end

# frozen_string_literal: true

require "test_helper"

class Round62FeaturesTest < ActiveSupport::TestCase
  setup do
    @user = create_user
  end

  test "restore gift card partial proportional" do
    card = Commerce::GiftCard.create!(
      code: "GC#{SecureRandom.hex(4).upcase}",
      balance_cents: 0,
      initial_balance_cents: 5000,
      currency: "CNY",
      active: true
    )
    order = Commerce::Order.create!(
      public_id: "ord_r62g_#{SecureRandom.hex(4)}",
      order_number: "R62G#{SecureRandom.hex(3).upcase}",
      user: @user,
      status: "paid",
      subtotal_cents: 1000,
      total_cents: 500,
      gift_card_amount_cents: 500,
      currency: "CNY",
      gift_card: card
    )

    result = Commerce::RestoreGiftCardPartial.call(
      order: order,
      refund_amount_cents: 250,
      payment_amount_cents: 500
    )
    assert result.success?
    assert_equal 250, result.value[:restored_cents]
    assert_equal 250, card.reload.balance_cents
    assert_equal 250, order.reload.gift_card_restored_cents
  end

  test "tag group required flag in section serialization" do
    category = Community::Category.find_or_create_by!(slug: "r62-cat-#{SecureRandom.hex(4)}") { |c| c.name = "R62" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r62-sec-#{SecureRandom.hex(4)}") { |s| s.name = "S"; s.position = 0 }
    group = Community::TagGroup.create!(name: "ReqG", slug: "r62-req-#{SecureRandom.hex(3)}")
    tag = Community::Tag.create!(name: "ReqTag", slug: "r62-rt-#{SecureRandom.hex(3)}")
    Community::TagGroupMembership.create!(tag_group: group, tag: tag)
    section.update!(required_tag_group_ids: [ group.id ])

    controller = Community::TopicsController.new
    groups = controller.send(:section_tag_groups_for, section, user: @user)
    required = groups.find { |g| g[:slug] == group.slug }
    assert required[:required]
  end

  test "serialize topic tag includes group color" do
    group = Community::TagGroup.create!(name: "ColG", slug: "r62-cg-#{SecureRandom.hex(3)}", color_hex: "#aabbcc")
    tag = Community::Tag.create!(name: "ColTag", slug: "r62-ct-#{SecureRandom.hex(3)}")
    Community::TagGroupMembership.create!(tag_group: group, tag: tag)

    assert_equal "#aabbcc", tag.tag_groups.first.color_hex
  end
end

class Round62WishlistUpcomingDisplayTest < ActionDispatch::IntegrationTest
  test "wishlist shows coming soon product with preview url" do
    user = create_user
    product = Commerce::Product.create!(
      name: "Wish Soon",
      slug: "r62-wish-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 100,
      currency: "CNY",
      minimum_quantity: 1,
      public_id: "pub_w62_#{SecureRandom.hex(4)}",
      available_at: 2.days.from_now
    )
    Commerce::WishlistItem.create!(user: user, product: product)

    sign_in_as(user)
    get store_wishlist_path
    assert_response :success
    assert_includes response.body, "Wish Soon"
    assert_includes response.body, "coming_soon"
    assert_includes response.body, "/preview"
  end
end

class Round62AddWishlistToCartSkipsUpcomingTest < ActiveSupport::TestCase
  test "add all to cart skips upcoming items" do
    user = create_user
    available = Commerce::Product.create!(
      name: "Avail", slug: "r62-av-#{SecureRandom.hex(4)}",
      product_type: "virtual", status: :active, price_cents: 100,
      currency: "CNY", minimum_quantity: 1, stock: 10
    )
    upcoming = Commerce::Product.create!(
      name: "Soon", slug: "r62-soon-#{SecureRandom.hex(4)}",
      product_type: "virtual", status: :active, price_cents: 100,
      currency: "CNY", minimum_quantity: 1, available_at: 2.days.from_now
    )
    Commerce::WishlistItem.create!(user: user, product: available)
    Commerce::WishlistItem.create!(user: user, product: upcoming)

    result = Commerce::AddWishlistToCart.call(user: user)
    assert result.success?
    assert_equal 1, result.value[:added]
    assert result.value[:skipped].any? { |s| s.include?("未上架") }
  end
end

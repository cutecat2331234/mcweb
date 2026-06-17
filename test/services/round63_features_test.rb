# frozen_string_literal: true

require "test_helper"

class Round63RequiredTagGroupPublishTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r63-cat-#{SecureRandom.hex(4)}") { |c| c.name = "R63" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r63-sec-#{SecureRandom.hex(4)}") { |s| s.name = "S"; s.position = 0 }
    @group = Community::TagGroup.create!(name: "ReqG63", slug: "r63-req-#{SecureRandom.hex(3)}")
    @tag = Community::Tag.create!(name: "ReqTag63", slug: "r63-rt-#{SecureRandom.hex(3)}")
    Community::TagGroupMembership.create!(tag_group: @group, tag: @tag)
    @section.update!(required_tag_group_ids: [ @group.id ])
  end

  test "create topic rejects missing required tag group" do
    result = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "No tags",
      body: "Body text here"
    )
    assert result.failure?
    assert_match(/标签组/, result.error)
  end

  test "publish draft rejects missing required tag group" do
    topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.hex(8)}",
      section: @section,
      user: @user,
      title: "Draft",
      status: :draft,
      last_posted_at: Time.current,
      last_post_user: @user
    )
    Community::Post.create!(topic: topic, user: @user, floor_number: 1, body: "Draft body", status: :published)

    result = Community::PublishTopicDraft.call(user: @user, topic: topic)
    assert result.failure?
    assert_match(/标签组/, result.error)
  end

  test "section requires_tags_or_groups helper" do
    assert @section.requires_tags_or_groups?
    assert_match(/ReqG63/, @section.tag_requirements_message)
  end
end

class Round63GiftCardFullRefundBoundaryTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @admin = create_user
    grant_permission(@admin, "store.orders.refund")
  end

  test "full refund after partial does not double restore gift card" do
    card = Commerce::GiftCard.create!(
      code: "GC#{SecureRandom.hex(4).upcase}",
      balance_cents: 0,
      initial_balance_cents: 5000,
      currency: "CNY",
      active: true
    )
    order = Commerce::Order.create!(
      public_id: "ord_r63g_#{SecureRandom.hex(4)}",
      order_number: "R63G#{SecureRandom.hex(3).upcase}",
      user: @user,
      status: "paid",
      subtotal_cents: 1000,
      total_cents: 500,
      gift_card_amount_cents: 500,
      currency: "CNY",
      gift_card: card
    )
    payment = Payments::Record.create!(
      order: order,
      provider: "fake",
      status: "succeeded",
      amount_cents: 500,
      currency: "CNY",
      provider_payment_id: "r63g_pay_#{SecureRandom.hex(4)}"
    )

    partial = Commerce::ProcessRefund.call(
      order: order,
      payment_record: payment,
      amount_cents: 250,
      approved_by: @admin
    )
    assert partial.success?
    assert_equal 250, card.reload.balance_cents
    assert_equal 250, order.reload.gift_card_restored_cents

    full = Commerce::ProcessRefund.call(
      order: order,
      payment_record: payment,
      amount_cents: 250,
      approved_by: @admin
    )
    assert full.success?
    assert_equal 500, card.reload.balance_cents
    assert_equal 500, order.reload.gift_card_restored_cents
  end
end

class Round63WishlistComingSoonTest < ActionDispatch::IntegrationTest
  test "wishlist note update works for coming soon product" do
    user = create_user
    product = Commerce::Product.create!(
      name: "Note Soon",
      slug: "r63-note-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 100,
      currency: "CNY",
      minimum_quantity: 1,
      public_id: "pub_n63_#{SecureRandom.hex(4)}",
      available_at: 2.days.from_now
    )
    Commerce::WishlistItem.create!(user: user, product: product)

    sign_in_as(user)
    patch store_note_wishlist_path(product.public_id), params: { note: "等上架" }
    assert_redirected_to store_wishlist_path
    assert_equal "等上架", Commerce::WishlistItem.find_by(user: user, product: product).note
  end

  test "public wishlist shows coming soon preview url" do
    user = create_user
    user.update!(wishlist_share_token: "r63share#{SecureRandom.hex(8)}")
    product = Commerce::Product.create!(
      name: "Public Soon",
      slug: "r63-pub-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 100,
      currency: "CNY",
      minimum_quantity: 1,
      public_id: "pub_p63_#{SecureRandom.hex(4)}",
      available_at: 2.days.from_now
    )
    Commerce::WishlistItem.create!(user: user, product: product)

    get store_public_wishlist_path(user.wishlist_share_token)
    assert_response :success
    assert_includes response.body, "Public Soon"
    assert_includes response.body, "coming_soon"
    assert_includes response.body, "/preview"
  end
end

class Round63OrderRestorationsTest < ActionDispatch::IntegrationTest
  test "order page includes restoration summary" do
    user = create_user
    order = Commerce::Order.create!(
      public_id: "ord_r63o_#{SecureRandom.hex(4)}",
      order_number: "R63O#{SecureRandom.hex(3).upcase}",
      user: user,
      status: "refunded",
      subtotal_cents: 1000,
      total_cents: 700,
      store_credit_amount_cents: 300,
      store_credit_restored_cents: 150,
      gift_card_restored_cents: 50,
      coupon_usage_restored: true,
      currency: "CNY"
    )
    coupon = Commerce::Coupon.create!(
      code: "R63CPN",
      discount_type: "fixed",
      discount_value: 10,
      active: true
    )
    order.update!(coupon: coupon)

    sign_in_as(user)
    get store_order_path(order)
    assert_response :success
    assert_includes response.body, "restorations"
    assert_includes response.body, "商店余额已恢复"
    assert_includes response.body, "礼品卡余额已恢复"
    assert_includes response.body, "优惠券使用次数已恢复"
  end
end

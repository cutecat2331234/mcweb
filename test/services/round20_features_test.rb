# frozen_string_literal: true

require "test_helper"

class Community::VotePollMultiTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r20-cat") { |c| c.name = "R20" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r20-sec") do |s|
      s.name = "R20 Sec"
      s.position = 0
    end
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @user,
      title: "Poll topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user
    )
    @poll = Community::Poll.create!(
      topic: @topic,
      question: "Pick many",
      options: %w[A B C],
      multiple_choice: true,
      max_choices: 2
    )
  end

  test "allows multiple votes" do
    result = Community::VotePoll.call(user: @user, poll: @poll, option_indices: [ 0, 2 ])
    assert result.success?
    assert_equal [ 0, 2 ], @poll.user_vote_indices(@user)
  end
end

class Community::ClosePollTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r20c-cat") { |c| c.name = "R20C" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r20c-sec") do |s|
      s.name = "R20C Sec"
      s.position = 0
    end
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @user,
      title: "Close poll",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user
    )
    @poll = Community::Poll.create!(topic: @topic, question: "Q?", options: %w[Yes No])
  end

  test "closes poll" do
    result = Community::ClosePoll.call(user: @user, poll: @poll)
    assert result.success?
    assert_not @poll.reload.open?
  end
end

class Community::UpdateBookmarkTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r20b-cat") { |c| c.name = "R20B" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r20b-sec") do |s|
      s.name = "R20B Sec"
      s.position = 0
    end
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @user,
      title: "Bookmark",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user
    )
    @bookmark = Community::Bookmark.create!(user: @user, topic: @topic)
  end

  test "updates note and remind_at" do
    result = Community::UpdateBookmark.call(
      user: @user,
      bookmark: @bookmark,
      note: "read later",
      remind_at: 1.day.from_now.iso8601
    )
    assert result.success?
    assert_equal "read later", @bookmark.reload.note
    assert @bookmark.remind_at.present?
  end
end

class Community::FormatPostBodyRound20Test < ActiveSupport::TestCase
  test "renders blockquote and table" do
    body = "> quoted line\n\n| A | B |\n|---|---|\n| 1 | 2 |"
    result = Community::FormatPostBody.call(body: body)
    assert result.success?
    assert_includes result.value, "<blockquote"
    assert_includes result.value, "<table"
  end

  test "renders ordered list" do
    result = Community::FormatPostBody.call(body: "1. first\n2. second")
    assert result.success?
    assert_includes result.value, "<ol>"
  end
end

class Commerce::CouponRestrictionsTest < ActiveSupport::TestCase
  setup do
    @category = Commerce::Category.find_or_create_by!(slug: "r20-shop") { |c| c.name = "R20 Shop" }
    @product = Commerce::Product.create!(
      public_id: "prod_r20_#{SecureRandom.hex(4)}",
      name: "Restricted",
      slug: "restricted-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 1000,
      currency: "CNY",
      stock: 5,
      category: @category
    )
    @coupon = Commerce::Coupon.create!(
      code: "R20ONLY",
      discount_type: "fixed",
      discount_value: 100,
      product_ids: [ @product.id ],
      category_ids: [ @category.id ]
    )
    @cart = Commerce::Cart.create!
    @cart.add_item!(product: @product, quantity: 1)
  end

  test "coupon applies to matching cart" do
    result = Commerce::PreviewCoupon.call(
      subtotal_cents: @cart.subtotal_cents,
      code: @coupon.code,
      cart_items: @cart.items.includes(:product)
    )
    assert result.success?
  end

  test "coupon rejects empty cart restrictions mismatch" do
    other = Commerce::Product.create!(
      public_id: "prod_r20o_#{SecureRandom.hex(4)}",
      name: "Other",
      slug: "other-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      stock: 5
    )
    cart = Commerce::Cart.create!
    cart.add_item!(product: other, quantity: 1)
    result = Commerce::PreviewCoupon.call(
      subtotal_cents: cart.subtotal_cents,
      code: @coupon.code,
      cart_items: cart.items.includes(:product)
    )
    assert result.failure?
  end
end

class Commerce::WishlistVariantTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_wl_#{SecureRandom.hex(4)}",
      name: "Variant WL",
      slug: "variant-wl-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 5
    )
    @variant = Commerce::ProductVariant.create!(
      product: @product,
      name: "Large",
      sku: "L-#{SecureRandom.hex(3)}",
      price_cents: 150,
      stock: 3
    )
  end

  test "stores variant on wishlist" do
    result = Commerce::ToggleWishlist.call(user: @user, product: @product, variant: @variant)
    assert result.success?
    item = Commerce::WishlistItem.find_by(user: @user, product: @product)
    assert_equal @variant.id, item.variant_id
  end
end

class Commerce::GenerateDownloadTokenTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @order = Commerce::Order.create!(
      user: @user,
      order_number: "ORD-DL-#{SecureRandom.hex(4)}",
      status: "paid",
      subtotal_cents: 500,
      discount_cents: 0,
      total_cents: 500,
      currency: "CNY"
    )
    @product = Commerce::Product.create!(
      public_id: "prod_dl_#{SecureRandom.hex(4)}",
      name: "Digital",
      slug: "digital-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      stock: nil,
      fulfillment_config: { download_url: "https://example.com/file.zip" }
    )
    @item = Commerce::OrderItem.create!(
      order: @order,
      product: @product,
      product_name: @product.name,
      quantity: 1,
      unit_price_cents: 500,
      total_cents: 500,
      fulfillment_snapshot: { fulfillment_config: { download_url: "https://example.com/file.zip" } }
    )
  end

  test "generates download token" do
    result = Commerce::GenerateDownloadToken.call(order_item: @item, user: @user)
    assert result.success?
    assert result.value[:token].present?
  end
end

class Commerce::RejectRefundEmailTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create_user
    @admin = create_user
    @order = Commerce::Order.create!(
      user: @user,
      order_number: "ORD-RR20-#{SecureRandom.hex(4)}",
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

  test "enqueues rejection email" do
    assert_enqueued_with(job: MailDeliveryJob) do
      Commerce::RejectRefund.call(refund: @refund, actor: @admin, reason: "no")
    end
  end
end

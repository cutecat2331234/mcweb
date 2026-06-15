# frozen_string_literal: true

require "test_helper"

class Community::TrustLevelProgressTest < ActiveSupport::TestCase
  test "progress_for shows posts needed for next level" do
    user = create_user
    progress = Community::TrustLevel.progress_for(user)
    assert_equal 0, progress[:level]
    assert_equal 1, progress[:posts_needed]
    assert_equal false, progress[:can_send_pm]
  end
end

class Community::CreateTopicPollHideTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    grant_permission(@user, "forum.topics.create")
    category = Community::Category.find_or_create_by!(slug: "r22-cat") { |c| c.name = "R22" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r22-sec") do |s|
      s.name = "R22 Sec"
      s.position = 0
    end
  end

  test "creates poll with hide results until vote" do
    result = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Poll hide test",
      body: "Body content here",
      poll_question: "Pick one",
      poll_options: %w[A B],
      poll_hide_results_until_vote: true
    )
    assert result.success?
    assert result.value.poll.hide_results_until_vote?
  end
end

class Commerce::ToggleWishlistVariantTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_tw_#{SecureRandom.hex(4)}",
      name: "Wishlist variant",
      slug: "wishlist-variant-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      stock: 5
    )
    @variant_a = Commerce::ProductVariant.create!(
      product: @product,
      name: "A",
      sku: "SKU-A-#{SecureRandom.hex(3)}",
      price_cents: 500,
      stock: 5
    )
    @variant_b = Commerce::ProductVariant.create!(
      product: @product,
      name: "B",
      sku: "SKU-B-#{SecureRandom.hex(3)}",
      price_cents: 600,
      stock: 5
    )
  end

  test "updates variant instead of removing when different variant selected" do
    Commerce::WishlistItem.create!(user: @user, product: @product, variant: @variant_a)
    result = Commerce::ToggleWishlist.call(user: @user, product: @product, variant: @variant_b)
    assert result.success?
    assert result.value[:wishlisted]
    item = Commerce::WishlistItem.find_by!(user: @user, product: @product)
    assert_equal @variant_b.id, item.variant_id
  end
end

class Commerce::ToggleCompareTest < ActiveSupport::TestCase
  setup do
    @product = Commerce::Product.create!(
      public_id: "prod_cmp_#{SecureRandom.hex(4)}",
      name: "Compare",
      slug: "compare-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 5
    )
    @session = {}
  end

  test "adds and removes product from compare session" do
    add = Commerce::ToggleCompare.call(session: @session, product: @product)
    assert add.success?
    assert add.value[:compared]
    assert_includes @session[:compare_product_ids], @product.public_id

    remove = Commerce::ToggleCompare.call(session: @session, product: @product)
    assert remove.success?
    assert_not remove.value[:compared]
    assert_empty @session[:compare_product_ids]
  end
end

class Commerce::CouponChineseReasonTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @coupon = Commerce::Coupon.create!(
      code: "PERUSER",
      discount_type: "fixed",
      discount_value: 100,
      per_user_limit: 1
    )
    Commerce::Order.create!(
      user: @user,
      order_number: "ORD-PU-#{SecureRandom.hex(4)}",
      status: "paid",
      subtotal_cents: 500,
      discount_cents: 100,
      total_cents: 400,
      currency: "CNY",
      store_coupon_id: @coupon.id
    )
  end

  test "returns chinese reason for per user limit" do
    reason = @coupon.inapplicable_reason(subtotal_cents: 1000, user: @user)
    assert_equal "已达到每人限用次数", reason
  end

  test "preview coupon uses chinese errors" do
    result = Commerce::PreviewCoupon.call(subtotal_cents: 1000, code: @coupon.code, user: @user)
    assert result.failure?
    assert_equal "已达到每人限用次数", result.error
  end

  test "per user limit counts pending orders" do
    Commerce::Order.create!(
      user: @user,
      order_number: "ORD-PU-PEND-#{SecureRandom.hex(4)}",
      status: "pending",
      subtotal_cents: 500,
      discount_cents: 100,
      total_cents: 400,
      currency: "CNY",
      store_coupon_id: @coupon.id
    )

    reason = @coupon.inapplicable_reason(subtotal_cents: 1000, user: @user)
    assert_equal "已达到每人限用次数", reason
  end
end

class Commerce::AddWishlistItemToCartTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_wc_#{SecureRandom.hex(4)}",
      name: "Wishlist cart",
      slug: "wishlist-cart-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 200,
      currency: "CNY",
      stock: 5
    )
    Commerce::WishlistItem.create!(user: @user, product: @product)
  end

  test "adds single wishlist item to cart" do
    result = Commerce::AddWishlistItemToCart.call(user: @user, product: @product)
    assert result.success?
    cart = Commerce::Cart.find_by!(user: @user)
    assert_equal 1, cart.items.count
  end
end

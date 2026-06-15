# frozen_string_literal: true

require "test_helper"

class Round61FeaturesTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @admin = create_user
    grant_permission(@admin, "store.orders.refund")
  end

  test "restore coupon when cumulative refund reaches full payment" do
    coupon = Commerce::Coupon.create!(
      code: "R61#{SecureRandom.hex(3).upcase}",
      discount_type: "fixed",
      discount_value: 100,
      active: true,
      used_count: 1
    )
    order = Commerce::Order.create!(
      public_id: "ord_r61c_#{SecureRandom.hex(4)}",
      order_number: "R61C#{SecureRandom.hex(3).upcase}",
      user: @user,
      status: "paid",
      subtotal_cents: 1000,
      total_cents: 900,
      discount_cents: 100,
      currency: "CNY",
      coupon: coupon
    )
    payment = Payments::Record.create!(
      order: order,
      provider: "fake",
      status: "succeeded",
      amount_cents: 900,
      currency: "CNY",
      provider_payment_id: "r61c_pay_#{SecureRandom.hex(4)}"
    )

    result = Commerce::RestoreCouponPartial.call(
      order: order,
      refund_amount_cents: 450,
      payment_amount_cents: 900,
      already_refunded_cents: 450
    )
    assert result.success?
    assert result.value[:restored]
    assert order.reload.coupon_usage_restored?
    assert_equal 0, coupon.reload.used_count
  end

  test "coupon not restored on partial refund below full amount" do
    coupon = Commerce::Coupon.create!(
      code: "R61P#{SecureRandom.hex(3).upcase}",
      discount_type: "fixed",
      discount_value: 50,
      active: true,
      used_count: 1
    )
    order = Commerce::Order.create!(
      public_id: "ord_r61p_#{SecureRandom.hex(4)}",
      order_number: "R61P#{SecureRandom.hex(3).upcase}",
      user: @user,
      status: "paid",
      subtotal_cents: 500,
      total_cents: 450,
      currency: "CNY",
      coupon: coupon
    )

    result = Commerce::RestoreCouponPartial.call(
      order: order,
      refund_amount_cents: 200,
      payment_amount_cents: 450,
      already_refunded_cents: 0
    )
    assert result.success?
    assert_not result.value[:restored]
    assert_equal 1, coupon.reload.used_count
  end

  test "section tag groups serializable concern" do
    category = Community::Category.find_or_create_by!(slug: "r61-cat-#{SecureRandom.hex(4)}") { |c| c.name = "R61" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r61-sec-#{SecureRandom.hex(4)}") { |s| s.name = "S"; s.position = 0 }
    group = Community::TagGroup.create!(name: "G61", slug: "r61-g-#{SecureRandom.hex(3)}")
    tag = Community::Tag.create!(name: "T61", slug: "r61-t-#{SecureRandom.hex(3)}")
    Community::TagGroupMembership.create!(tag_group: group, tag: tag)

    controller = Community::TopicsController.new
    groups = controller.send(:section_tag_groups_for, section, user: @user)
    assert groups.any? { |g| g[:slug] == group.slug }
  end
end

class Round61WishlistUpcomingTest < ActiveSupport::TestCase
  test "toggle wishlist allows upcoming products" do
    user = create_user
    product = Commerce::Product.create!(
      name: "Wish Upcoming",
      slug: "r61-wish-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 100,
      currency: "CNY",
      minimum_quantity: 1,
      public_id: "pub_wish_#{SecureRandom.hex(4)}",
      available_at: 2.days.from_now
    )

    result = Commerce::ToggleWishlist.call(user: user, product: product)
    assert result.success?
    assert result.value[:wishlisted]
  end
end

class Round61SearchStaffFiltersTest < ActionDispatch::IntegrationTest
  test "staff search exposes forumStaff prop" do
    mod = create_user
    grant_permission(mod, "forum.topics.lock")
    sign_in_as(mod)

    get forum_search_path, params: { q: "test", featured: "featured" }
    assert_response :success
    assert_includes response.body, '"forumStaff":true'
    assert_includes response.body, '"featured":"featured"'
  end
end

class Round61StaffLowStockPreferenceTest < ActionDispatch::IntegrationTest
  test "staff sees low stock preference" do
    staff = create_user
    grant_permission(staff, "store.products.read")
    sign_in_as(staff)

    get store_preferences_path
    assert_response :success
    assert_includes response.body, "commerce.low_stock"
  end
end

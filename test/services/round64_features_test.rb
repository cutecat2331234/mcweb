# frozen_string_literal: true

require "test_helper"

class Round64WarningRestrictionsPropsTest < ActionDispatch::IntegrationTest
  test "new topic page exposes warning restrictions" do
    user = create_user
    category = Community::Category.find_or_create_by!(slug: "r64-cat-#{SecureRandom.hex(4)}") { |c| c.name = "R64" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r64-sec-#{SecureRandom.hex(4)}") { |s| s.name = "S"; s.position = 0 }

    SiteSetting.set("forum.warning_block_post_threshold", "3")
    mod = create_user
    grant_permission(mod, "forum.users.warn")
    Community::UserWarning.create!(user: user, issuer: mod, reason: "Spam", points: 3)

    sign_in_as(user)
    get new_forum_topic_path(section_id: section.slug)
    assert_response :success
    assert_includes response.body, "warningRestrictions"
    assert_includes response.body, "暂时无法发帖"
  end
end

class Round64WishlistCompareTest < ActionDispatch::IntegrationTest
  test "wishlist exposes compare toggle for available products" do
    user = create_user
    product = Commerce::Product.create!(
      name: "Compare Wish",
      slug: "r64-cmp-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 100,
      currency: "CNY",
      minimum_quantity: 1,
      stock: 5,
      public_id: "pub_c64_#{SecureRandom.hex(4)}"
    )
    Commerce::WishlistItem.create!(user: user, product: product)

    sign_in_as(user)
    get store_wishlist_path
    assert_response :success
    assert_includes response.body, "compare_url"
    assert_includes response.body, "/store/compare/toggle"
  end
end

class Round64AdminOrderRestorationsTest < ActionDispatch::IntegrationTest
  test "admin order shows restoration section" do
    admin = create_user
    grant_permission(admin, "admin.access")
    grant_permission(admin, "store.orders.read")
    user = create_user
    order = Commerce::Order.create!(
      public_id: "ord_r64a_#{SecureRandom.hex(4)}",
      order_number: "R64A#{SecureRandom.hex(3).upcase}",
      user: user,
      status: "refunded",
      subtotal_cents: 1000,
      total_cents: 800,
      store_credit_restored_cents: 100,
      currency: "CNY"
    )

    sign_in_as(admin)
    get admin_store_order_path(order)
    assert_response :success
    assert_includes response.body, "退款恢复明细"
    assert_includes response.body, "商店余额已恢复"
  end
end

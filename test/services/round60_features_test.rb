# frozen_string_literal: true

require "test_helper"

class Round60FeaturesTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @admin = create_user
    grant_permission(@admin, "store.orders.refund")
  end

  test "partial refund restores proportional stock" do
    product = Commerce::Product.create!(
      name: "Stock Partial",
      slug: "r60-stock-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 1000,
      currency: "CNY",
      stock: 10,
      minimum_quantity: 1
    )
    cart = Commerce::Cart.create!(user: @user)
    Commerce::CartItem.create!(cart: cart, product: product, quantity: 2)

    order_result = Commerce::CreateOrder.call(cart: cart, user: @user)
    assert order_result.success?
    order = order_result.value
    assert_equal 8, product.reload.stock

    payment = Payments::Record.create!(
      order: order,
      provider: "fake",
      status: "succeeded",
      amount_cents: order.total_cents,
      currency: "CNY",
      provider_payment_id: "r60_pay_#{SecureRandom.hex(4)}"
    )
    order.update!(status: "paid")

    result = Commerce::ProcessRefund.call(
      order: order,
      payment_record: payment,
      amount_cents: payment.amount_cents / 2,
      approved_by: @admin
    )
    assert result.success?
    assert_equal 9, product.reload.stock
    assert_equal 1, order.items.first.reload.stock_restored_quantity
  end

  test "restore stock partial service" do
    product = Commerce::Product.create!(
      name: "Svc Stock",
      slug: "r60-svc-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      stock: 20,
      minimum_quantity: 1
    )
    order = Commerce::Order.create!(
      public_id: "ord_r60s_#{SecureRandom.hex(4)}",
      order_number: "R60S#{SecureRandom.hex(3).upcase}",
      user: @user,
      status: "paid",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY"
    )
    Commerce::OrderItem.create!(
      order: order,
      product: product,
      product_name: product.name,
      unit_price_cents: 500,
      quantity: 2,
      total_cents: 1000
    )
    product.update!(stock: 18)

    result = Commerce::RestoreStockPartial.call(
      order: order,
      refund_amount_cents: 500,
      payment_amount_cents: 1000
    )
    assert result.success?
    assert_equal 1, result.value[:restored_units]
    assert_equal 19, product.reload.stock
  end

  test "tag has tag_groups association" do
    group = Community::TagGroup.create!(name: "G60", slug: "r60-g-#{SecureRandom.hex(3)}", color_hex: "#00ff00")
    tag = Community::Tag.create!(name: "T60", slug: "r60-t-#{SecureRandom.hex(3)}", color_hex: "#ff0000")
    Community::TagGroupMembership.create!(tag_group: group, tag: tag)
    assert_includes tag.tag_groups, group
  end

  test "product available notification type in preferences" do
    assert_includes Commerce::PreferencesController::NOTIFICATION_TYPES, "commerce.product_available"
  end
end

class Round60ProductPreviewTest < ActionDispatch::IntegrationTest
  test "preview page for upcoming product" do
    product = Commerce::Product.create!(
      name: "Preview Item",
      slug: "r60-preview-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 100,
      currency: "CNY",
      minimum_quantity: 1,
      public_id: "pub_r60_#{SecureRandom.hex(4)}",
      available_at: 2.days.from_now
    )

    get preview_store_product_path(product)
    assert_response :success
    assert_includes response.body, "Preview Item"
    assert_includes response.body, "Commerce/Products/Preview"
    assert_includes response.body, "coming_soon_label"
  end
end

class Round60TagsIndexGroupedTest < ActionDispatch::IntegrationTest
  test "tags index returns grouped props" do
    user = create_user
    group = Community::TagGroup.create!(name: "Grouped", slug: "r60-grp-#{SecureRandom.hex(3)}")
    tag = Community::Tag.create!(name: "GroupedTag", slug: "r60-gtag-#{SecureRandom.hex(3)}")
    Community::TagGroupMembership.create!(tag_group: group, tag: tag)

    sign_in_as(user)
    get forum_tags_path
    assert_response :success
    assert_includes response.body, "tagGroups"
    assert_includes response.body, "Grouped"
  end
end

class Round60SearchAdvancedFiltersTest < ActionDispatch::IntegrationTest
  test "search accepts scope and poll filters" do
    user = create_user
    sign_in_as(user)

    get forum_search_path, params: { q: "test", scope: "bookmarks", poll: "poll" }
    assert_response :success
    assert_includes response.body, '"scope":"bookmarks"'
  end
end

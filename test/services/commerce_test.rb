# frozen_string_literal: true

require "test_helper"

class Commerce::ConfirmPaymentTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_test123",
      order_number: "ORD-TEST-001",
      user: @user,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 1000,
      discount_cents: 0,
      currency: "CNY"
    )
    @payment = Payments::Record.create!(
      order: @order,
      provider: "fake",
      status: "pending",
      amount_cents: 1000,
      currency: "CNY"
    )
  end

  test "confirms payment and updates order" do
    result = Commerce::ConfirmPayment.call(
      payment_record: @payment,
      provider_payment_id: "fake_pay_123"
    )

    assert result.success?
    assert_equal "succeeded", @payment.reload.status
    assert_equal "paid", @order.reload.status
  end

  test "is idempotent for duplicate callbacks" do
    Commerce::ConfirmPayment.call(payment_record: @payment, provider_payment_id: "fake_pay_123")
    result = Commerce::ConfirmPayment.call(payment_record: @payment, provider_payment_id: "fake_pay_123")

    assert result.success?
    assert result.value[:idempotent]
    assert_equal 1, Payments::Record.where(order: @order, status: "succeeded").count
  end

  test "rejects payment confirmation for cancelled order" do
    @order.update!(status: "cancelled")

    result = Commerce::ConfirmPayment.call(payment_record: @payment, provider_payment_id: "late_pay")

    assert result.failure?
    assert_equal "pending", @payment.reload.status
    assert_equal "cancelled", @order.reload.status
  end

  test "rejects payment confirmation for failed payment record" do
    @payment.update!(status: "failed")

    result = Commerce::ConfirmPayment.call(payment_record: @payment, provider_payment_id: "late_pay")

    assert result.failure?
    assert_equal "failed", @payment.reload.status
  end

  test "allows zero amount payment records" do
    payment = Payments::Record.new(
      order: @order,
      provider: "fake",
      status: "pending",
      amount_cents: 0,
      currency: "CNY"
    )

    assert payment.valid?
  end
end

class Commerce::DebitStoreCreditTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @user.update!(store_credit_cents: 500)
    @order = Commerce::Order.create!(
      public_id: "ord_sc_#{SecureRandom.hex(6)}",
      order_number: "SC#{SecureRandom.hex(4)}",
      user: @user,
      status: "paid",
      subtotal_cents: 1000,
      total_cents: 700,
      store_credit_amount_cents: 300,
      currency: "CNY"
    )
  end

  test "debits store credit for order" do
    Commerce::DebitStoreCredit.call(order: @order)
    assert_equal 200, @user.reload.store_credit_cents
    assert_equal 1, @user.store_credit_transactions.where(order: @order).count
  end

  test "debit store credit is idempotent" do
    Commerce::DebitStoreCredit.call(order: @order)
    Commerce::DebitStoreCredit.call(order: @order)
    assert_equal 200, @user.reload.store_credit_cents
    assert_equal 1, @user.store_credit_transactions.where(order: @order).where("amount_cents < 0").count
  end

  test "fails when store credit balance is insufficient" do
    @user.update!(store_credit_cents: 100)
    result = Commerce::DebitStoreCredit.call(order: @order)
    assert_not result.success?
    assert_equal "商店余额不足。", result.error
    assert_equal 100, @user.reload.store_credit_cents
    assert_equal 0, @user.store_credit_transactions.where(order: @order).count
  end
end

class Commerce::CreateFulfillmentTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_fulfill1",
      order_number: "ORD-FUL-001",
      user: @user,
      status: "paid",
      subtotal_cents: 500,
      total_cents: 500,
      discount_cents: 0,
      currency: "CNY"
    )
    @item = Commerce::OrderItem.create!(
      order: @order,
      product_name: "VIP",
      unit_price_cents: 500,
      quantity: 1,
      total_cents: 500,
      fulfillment_snapshot: { commands: [ "say hello" ] }
    )
  end

  test "creates fulfillment with unique delivery_id" do
    result = Commerce::CreateFulfillment.call(order_item: @item)
    assert result.success?
    assert result.value.delivery_id.present?
  end

  test "duplicate delivery_id is prevented" do
    first = Commerce::CreateFulfillment.call(order_item: @item)
    assert first.success?

    duplicate_item = Commerce::OrderItem.create!(
      order: @order,
      product_name: "VIP",
      unit_price_cents: 500,
      quantity: 1,
      total_cents: 500,
      fulfillment_snapshot: { commands: [ "say hello" ] }
    )

    # Same order item should not create duplicate
    second = Commerce::CreateFulfillment.call(order_item: @item)
    assert second.success?
    assert_equal 1, Commerce::Fulfillment.where(order_item: @item).count
    assert duplicate_item # silence unused warning
  end
end

class Commerce::ApplyCouponTest < ActiveSupport::TestCase
  test "applies fixed discount" do
    user = create_user
    order = Commerce::Order.create!(
      public_id: "ord_coupon1",
      order_number: "ORD-COUP-001",
      user: user,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 1000,
      discount_cents: 0,
      currency: "CNY"
    )
    Commerce::Coupon.create!(
      code: "SAVE100",
      discount_type: "fixed",
      discount_value: 100,
      active: true
    )

    result = Commerce::ApplyCoupon.call(order: order, code: "SAVE100")
    assert result.success?
    assert_equal 100, order.reload.discount_cents
    assert_equal 900, order.total_cents
  end
end

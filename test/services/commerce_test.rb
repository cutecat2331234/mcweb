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

  test "rejects payment confirmation for expired pending order" do
    SiteSetting.set("store.pending_order_expiry_minutes", "30")
    @order.update!(created_at: 2.hours.ago)

    result = Commerce::ConfirmPayment.call(payment_record: @payment, provider_payment_id: "late_pay")

    assert result.failure?
    assert_equal "订单支付已过期。", result.error
    assert_equal "pending", @payment.reload.status
    assert_equal "pending", @order.reload.status
  end

  test "rejects payment when amount does not match order total" do
    @payment.update!(amount_cents: 500)

    result = Commerce::ConfirmPayment.call(payment_record: @payment, provider_payment_id: "mismatch_pay")

    assert result.failure?
    assert_equal "支付金额与订单不符。", result.error
    assert_equal "pending", @payment.reload.status
    assert_equal "pending", @order.reload.status
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

  test "fails when user association is missing" do
    order = @order
    def order.user
      nil
    end

    result = Commerce::DebitStoreCredit.call(order: order)
    assert result.failure?
    assert_equal "用户信息无效。", result.error
  end
end

class Commerce::RestoreStoreCreditTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @user.update!(store_credit_cents: 0)
    @order = Commerce::Order.create!(
      public_id: "ord_restore_sc_#{SecureRandom.hex(6)}",
      order_number: "RSC#{SecureRandom.hex(4)}",
      user: @user,
      status: "refunded",
      subtotal_cents: 1000,
      total_cents: 700,
      store_credit_amount_cents: 300,
      currency: "CNY"
    )
    Commerce::StoreCreditTransaction.create!(
      user: @user,
      order: @order,
      amount_cents: -300,
      note: "deduct"
    )
  end

  test "restores store credit balance" do
    result = Commerce::RestoreStoreCredit.call(order: @order)
    assert result.success?
    assert_equal 300, @user.reload.store_credit_cents
    assert_equal 0, @order.reload.store_credit_amount_cents
  end

  test "fails when user association is missing" do
    order = @order
    def order.user
      nil
    end

    result = Commerce::RestoreStoreCredit.call(order: order)
    assert result.failure?
    assert_equal "用户信息无效。", result.error
  end
end

class Commerce::CancelOrderCouponTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @coupon = Commerce::Coupon.create!(
      code: "CANCEL#{SecureRandom.hex(6).upcase}",
      discount_type: "fixed",
      discount_value: 100,
      active: true,
      used_count: 1
    )
    @order = Commerce::Order.create!(
      public_id: "ord_cancel_coupon_#{SecureRandom.hex(6)}",
      order_number: "CNC#{SecureRandom.hex(4)}",
      user: @user,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 900,
      discount_cents: 100,
      coupon: @coupon,
      currency: "CNY"
    )
  end

  test "restores coupon usage on cancel and marks flag" do
    @order.update_columns(coupon_usage_restored: false)

    result = Commerce::CancelOrder.call(order: @order, actor: @user)

    assert result.success?
    assert_equal 0, @coupon.reload.used_count
    assert @order.reload.coupon_usage_restored?
  end
end

class Commerce::ProcessRefundRestoreFailureTest < ActiveSupport::TestCase
  setup do
    @admin = create_user
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_ref_gift_#{SecureRandom.hex(6)}",
      order_number: "REFG#{SecureRandom.hex(4)}",
      user: @user,
      status: "paid",
      subtotal_cents: 1000,
      total_cents: 500,
      gift_card_amount_cents: 500,
      currency: "CNY"
    )
    @payment = Payments::Record.create!(
      order: @order,
      provider: "fake",
      status: "succeeded",
      amount_cents: 500,
      currency: "CNY",
      provider_payment_id: "fake_ref_gift_#{SecureRandom.hex(4)}"
    )
  end

  test "full refund rolls back when gift card association is missing" do
    result = Commerce::ProcessRefund.call(
      order: @order,
      payment_record: @payment,
      amount_cents: 500,
      reason: "Full refund",
      approved_by: @admin
    )

    assert result.failure?
    assert_equal "礼品卡信息无效。", result.error
    assert_equal "paid", @order.reload.status
    assert_equal "succeeded", @payment.reload.status
    assert_equal 0, @order.refunds.where(status: "completed").count
  end
end

class Commerce::PreviewCouponGiftWrapTest < ActiveSupport::TestCase
  test "preview coupon includes gift wrap in total" do
    Commerce::Coupon.create!(
      code: "WRAP10",
      discount_type: "fixed",
      discount_value: 100,
      active: true
    )
    result = Commerce::PreviewCoupon.call(subtotal_cents: 1000, code: "WRAP10", gift_wrap_cents: 300)
    assert result.success?
    assert_equal 1200, result.value[:total_cents]
  end
end

class Commerce::BulkUpdateOrdersMarkPaidTest < ActiveSupport::TestCase
  setup do
    @admin = create_user
    @user = create_user
    @user.update!(store_credit_cents: 100)
    @order = Commerce::Order.create!(
      public_id: "ord_bulk_#{SecureRandom.hex(6)}",
      order_number: "BULK#{SecureRandom.hex(4)}",
      user: @user,
      status: "awaiting_payment",
      subtotal_cents: 1000,
      total_cents: 700,
      store_credit_amount_cents: 300,
      currency: "CNY"
    )
  end

  test "bulk mark paid fails when store credit is insufficient" do
    result = Commerce::BulkUpdateOrders.call(
      actor: @admin,
      order_public_ids: [ @order.public_id ],
      action: "mark_paid"
    )
    assert result.success?
    assert_equal 0, result.value[:processed]
    assert_equal 1, result.value[:failed]
    assert_equal "awaiting_payment", @order.reload.status
    assert_equal 100, @user.reload.store_credit_cents
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

  test "applies coupon and preserves gift wrap fee" do
    user = create_user
    order = Commerce::Order.create!(
      public_id: "ord_coupon_wrap",
      order_number: "ORD-COUP-WRAP",
      user: user,
      status: "pending",
      subtotal_cents: 1000,
      shipping_cents: 0,
      gift_wrap_cents: 300,
      total_cents: 1300,
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
    order.reload
    assert_equal 100, order.discount_cents
    assert_equal 1200, order.total_cents
  end
end

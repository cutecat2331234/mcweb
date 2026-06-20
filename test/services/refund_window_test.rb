# frozen_string_literal: true

require "test_helper"

class Commerce::RefundWindowUnitTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_rw_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "paid",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY"
    )
    Payments::Record.create!(
      order: @order,
      provider: "fake",
      amount_cents: 1000,
      currency: "CNY",
      status: "succeeded"
    )
  end

  teardown do
    reset_refund_window!
  end

  test "disabled window blocks self-service refunds" do
    reset_refund_window!
    anchor_order_payment_at!(@order, paid_at: 1.day.ago)

    assert_not Commerce::RefundWindow.within_window?(@order)
    result = Commerce::RequestRefund.call(order: @order, user: @user, reason: "test")
    assert result.failure?
    assert_equal "Refund window has expired.", result.error
  end

  test "enabled window allows recent payments" do
    enable_refund_window!(7)
    anchor_order_payment_at!(@order, paid_at: 2.days.ago)

    assert Commerce::RefundWindow.within_window?(@order)
    result = Commerce::RequestRefund.call(order: @order, user: @user, reason: "test")
    assert result.success?, result.error
  end

  test "enabled window rejects stale payments" do
    enable_refund_window!(7)
    anchor_order_payment_at!(@order, paid_at: 10.days.ago)

    assert_not Commerce::RefundWindow.within_window?(@order)
    result = Commerce::RequestRefund.call(order: @order, user: @user, reason: "late")
    assert result.failure?
    assert_equal "Refund window has expired.", result.error
  end
end

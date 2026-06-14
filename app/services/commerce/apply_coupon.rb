# frozen_string_literal: true

module Commerce
  class ApplyCoupon < ApplicationService
    def initialize(order:, code:)
      @order = order
      @code = code.to_s.strip.upcase
    end

    def call
      return ServiceResult.failure(error: "订单无法修改。") unless @order.status == "pending"

      coupon = Commerce::Coupon.find_by(code: @code)
      return ServiceResult.failure(error: "优惠券代码无效。") unless coupon

      reason = coupon.inapplicable_reason(
        subtotal_cents: @order.subtotal_cents,
        cart_items: @order.items.includes(:product),
        user: @order.user
      )
      return ServiceResult.failure(error: reason) if reason

      discount_cents = coupon.calculate_discount(@order.subtotal_cents, cart_items: @order.items.includes(:product), user: @order.user)
      shipping_cents = @order.shipping_cents.to_i
      total_cents = [ @order.subtotal_cents - discount_cents + shipping_cents, 0 ].max

      Commerce::Order.transaction do
        @order.update!(
          coupon: coupon,
          discount_cents: discount_cents,
          total_cents: total_cents
        )
        coupon.increment!(:used_count)
      end

      ServiceResult.success(order: @order, discount_cents: discount_cents)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

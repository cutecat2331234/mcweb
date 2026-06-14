# frozen_string_literal: true

module Commerce
  class ApplyCoupon < ApplicationService
    def initialize(order:, code:)
      @order = order
      @code = code.to_s.strip.upcase
    end

    def call
      return ServiceResult.failure(error: "Order cannot be modified.") unless @order.status == "pending"

      coupon = Commerce::Coupon.find_by(code: @code)
      return ServiceResult.failure(error: "Invalid coupon code.") unless coupon
      return ServiceResult.failure(error: "Coupon is not active.") unless coupon.active?
      return ServiceResult.failure(error: "Coupon is not yet valid.") if coupon.starts_at&.future?
      return ServiceResult.failure(error: "Coupon has expired.") if coupon.ends_at&.past?
      return ServiceResult.failure(error: "Coupon usage limit reached.") if coupon.usage_limit && coupon.used_count >= coupon.usage_limit
      return ServiceResult.failure(error: "Order does not meet minimum amount.") if @order.subtotal_cents < coupon.min_amount_cents
      unless coupon.applicable?(subtotal_cents: @order.subtotal_cents, cart_items: @order.items.includes(:product))
        return ServiceResult.failure(error: "Coupon is not applicable to order items.")
      end

      discount_cents = coupon.calculate_discount(@order.subtotal_cents, cart_items: @order.items.includes(:product))
      total_cents = [ @order.subtotal_cents - discount_cents, 0 ].max

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

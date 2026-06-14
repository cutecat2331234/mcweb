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

      discount_cents = calculate_discount(coupon)
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

    private

    def calculate_discount(coupon)
      case coupon.discount_type
      when "fixed"
        [ coupon.discount_value, @order.subtotal_cents ].min
      when "percent"
        (@order.subtotal_cents * coupon.discount_value / 100.0).floor
      else
        0
      end
    end
  end
end

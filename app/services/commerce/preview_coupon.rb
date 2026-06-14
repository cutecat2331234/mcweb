# frozen_string_literal: true

module Commerce
  class PreviewCoupon < ApplicationService
    def initialize(subtotal_cents:, code:, cart_items: nil)
      @subtotal_cents = subtotal_cents
      @code = code.to_s.strip.upcase
      @cart_items = cart_items
    end

    def call
      return ServiceResult.failure(error: "Coupon code is required.") if @code.blank?

      coupon = Commerce::Coupon.find_by(code: @code)
      return ServiceResult.failure(error: "Invalid coupon code.") unless coupon
      unless coupon.applicable?(subtotal_cents: @subtotal_cents, cart_items: @cart_items)
        return ServiceResult.failure(error: "Coupon is not applicable to cart items.")
      end

      discount_cents = coupon.calculate_discount(@subtotal_cents, cart_items: @cart_items)
      ServiceResult.success(
        code: coupon.code,
        discount_cents: discount_cents,
        total_cents: [ @subtotal_cents - discount_cents, 0 ].max
      )
    end
  end
end

# frozen_string_literal: true

module Commerce
  class PreviewCoupon < ApplicationService
    def initialize(subtotal_cents:, code:, cart_items: nil, user: nil, shipping_cents: nil, gift_wrap_cents: 0)
      @subtotal_cents = subtotal_cents
      @code = code.to_s.strip.upcase
      @cart_items = cart_items
      @user = user
      @shipping_cents = shipping_cents
      @gift_wrap_cents = gift_wrap_cents.to_i
    end

    def call
      return ServiceResult.failure(error: "coupon_code_required") if @code.blank?

      coupon = Commerce::Coupon.find_by(code: @code)
      return ServiceResult.failure(error: "coupon_unavailable") unless coupon

      reason = coupon.inapplicable_reason(subtotal_cents: @subtotal_cents, cart_items: @cart_items, user: @user)
      return ServiceResult.failure(error: "coupon_unavailable") if reason

      discount_cents = coupon.calculate_discount(@subtotal_cents, cart_items: @cart_items, user: @user)
      shipping_cents = resolved_shipping_cents(coupon)
      ServiceResult.success(
        code: coupon.code,
        discount_cents: discount_cents,
        shipping_cents: shipping_cents,
        total_cents: [ @subtotal_cents - discount_cents + shipping_cents + @gift_wrap_cents, 0 ].max,
        free_shipping: coupon.free_shipping?,
        min_amount_cents: coupon.min_amount_cents,
        min_amount_label: coupon.min_amount_cents.positive? ? format_money(coupon.min_amount_cents) : nil,
        amount_remaining_cents: coupon.min_amount_cents.positive? ? [ coupon.min_amount_cents - @subtotal_cents, 0 ].max : 0,
        amount_remaining_label: coupon.min_amount_cents.positive? && @subtotal_cents < coupon.min_amount_cents ? format_money(coupon.min_amount_cents - @subtotal_cents) : nil
      )
    end

    private

    def resolved_shipping_cents(coupon)
      return @shipping_cents.to_i unless @shipping_cents.nil?

      result = Commerce::CalculateShipping.call(
        subtotal_cents: @subtotal_cents,
        cart_items: @cart_items,
        coupon: coupon
      )
      result.success? ? result.value[:shipping_cents].to_i : 0
    end

    def format_money(cents)
      ActionController::Base.helpers.number_to_currency(cents / 100.0, unit: "¥")
    end
  end
end

# frozen_string_literal: true

module Commerce
  class PreviewCoupon < ApplicationService
    def initialize(subtotal_cents:, code:, cart_items: nil, user: nil)
      @subtotal_cents = subtotal_cents
      @code = code.to_s.strip.upcase
      @cart_items = cart_items
      @user = user
    end

    def call
      return ServiceResult.failure(error: "请输入优惠券代码。") if @code.blank?

      coupon = Commerce::Coupon.find_by(code: @code)
      return ServiceResult.failure(error: "优惠券代码无效。") unless coupon

      reason = coupon.inapplicable_reason(subtotal_cents: @subtotal_cents, cart_items: @cart_items, user: @user)
      return ServiceResult.failure(error: reason) if reason

      discount_cents = coupon.calculate_discount(@subtotal_cents, cart_items: @cart_items, user: @user)
      ServiceResult.success(
        code: coupon.code,
        discount_cents: discount_cents,
        total_cents: [ @subtotal_cents - discount_cents, 0 ].max,
        min_amount_cents: coupon.min_amount_cents,
        min_amount_label: coupon.min_amount_cents.positive? ? format_money(coupon.min_amount_cents) : nil,
        amount_remaining_cents: coupon.min_amount_cents.positive? ? [ coupon.min_amount_cents - @subtotal_cents, 0 ].max : 0,
        amount_remaining_label: coupon.min_amount_cents.positive? && @subtotal_cents < coupon.min_amount_cents ? format_money(coupon.min_amount_cents - @subtotal_cents) : nil
      )
    end

    private

    def format_money(cents)
      ActionController::Base.helpers.number_to_currency(cents / 100.0, unit: "¥")
    end
  end
end

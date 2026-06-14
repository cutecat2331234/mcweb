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
        total_cents: [ @subtotal_cents - discount_cents, 0 ].max
      )
    end
  end
end

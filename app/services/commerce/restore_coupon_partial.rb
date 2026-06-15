# frozen_string_literal: true

module Commerce
  class RestoreCouponPartial < ApplicationService
    def initialize(order:, refund_amount_cents:, payment_amount_cents:, already_refunded_cents: 0)
      @order = order
      @refund_amount_cents = refund_amount_cents.to_i
      @payment_amount_cents = payment_amount_cents.to_i
      @already_refunded_cents = already_refunded_cents.to_i
    end

    def call
      coupon = @order.coupon
      return ServiceResult.success(restored: false) unless coupon
      return ServiceResult.success(restored: false) if @order.coupon_usage_restored?

      total_refunded = @already_refunded_cents + @refund_amount_cents
      return ServiceResult.success(restored: false) unless @payment_amount_cents.positive?
      return ServiceResult.success(restored: false) unless total_refunded >= @payment_amount_cents

      Commerce::Order.transaction do
        @order.lock!
        unless @order.coupon_usage_restored?
          coupon.decrement!(:used_count) if coupon.used_count.positive?
          @order.update!(coupon_usage_restored: true)
        end
      end

      ServiceResult.success(restored: true)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

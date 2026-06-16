# frozen_string_literal: true

module Community
  class FetchCouponOnebox < ApplicationService
    COUPON_PATH = %r{\A(?:/app)?/store/coupons/([\w-]+)\z}i

    def initialize(url:)
      @url = url.to_s.strip
    end

    def call
      path = if @url.start_with?("/")
               @url
      else
               URI.parse(@url).path
      end
      return ServiceResult.success(nil) unless path

      match = path.match(COUPON_PATH)
      return ServiceResult.success(nil) unless match

      coupon = Commerce::Coupon.active_coupons.find_by(code: match[1].upcase)
      return ServiceResult.success(nil) unless coupon

      label = case coupon.discount_type
      when "percentage"
                "#{coupon.discount_value}% 折扣"
      when "fixed"
                "减 #{format_money(coupon.discount_value)}"
      else
                coupon.code
      end

      ServiceResult.success(
        code: coupon.code,
        discount_label: label,
        url: "/app/store/coupons/#{coupon.code}"
      )
    rescue URI::InvalidURIError
      ServiceResult.success(nil)
    end

    private

    def format_money(cents)
      ActionController::Base.helpers.number_to_currency(cents / 100.0, unit: "¥")
    end
  end
end

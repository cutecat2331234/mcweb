# frozen_string_literal: true

module Commerce
  class CouponsController < ApplicationController
    def show
      code = params[:code].to_s.strip.upcase
      coupon = Commerce::Coupon.active_coupons.find_by(code: code)

      unless coupon
        return render inertia: "Commerce/Coupons/Show", props: {
          coupon: nil,
          code: code,
          loggedIn: logged_in?
        }
      end

      render inertia: "Commerce/Coupons/Show", props: {
        coupon: {
          code: coupon.code,
          discount_type: coupon.discount_type,
          discount_label: discount_label(coupon),
          min_amount_label: coupon.min_amount_cents.positive? ? format_money(coupon.min_amount_cents) : nil,
          ends_at: coupon.ends_at ? l(coupon.ends_at, format: :short) : nil,
          first_order_only: coupon.first_order_only?,
          usage_remaining: coupon.usage_limit ? [ coupon.usage_limit - coupon.used_count, 0 ].max : nil,
          per_user_limit: coupon.per_user_limit,
          max_discount_label: coupon.max_discount_cents.present? && coupon.max_discount_cents.positive? ? format_money(coupon.max_discount_cents) : nil
        },
        code: code,
        loggedIn: logged_in?,
        applyUrl: apply_store_coupon_path(code: coupon.code)
      }
    end

    def apply
      require_login
      code = params[:code].to_s.strip.upcase
      coupon = Commerce::Coupon.active_coupons.find_by(code: code)
      return redirect_to store_coupon_path(code), alert: "优惠券无效。" unless coupon

      session[:pending_coupon_code] = coupon.code
      redirect_to store_cart_path, notice: "优惠码 #{coupon.code} 已保存，结账时自动使用。"
    end

    private

    def discount_label(coupon)
      case coupon.discount_type
      when "percentage"
        "#{coupon.discount_value}% 折扣"
      when "fixed"
        "减 #{format_money(coupon.discount_value)}"
      else
        coupon.code
      end
    end
  end
end

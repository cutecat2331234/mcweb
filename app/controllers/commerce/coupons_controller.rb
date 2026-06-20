# frozen_string_literal: true

module Commerce
  class CouponsController < ApplicationController
    include Commerce::CodePreviewRateLimitable

    def show
      code = params[:code].to_s.strip.upcase

      render inertia: "Commerce/Coupons/Show", props: {
        coupon: {
          code: code,
          available: false,
          status_label: t("mcweb.labels.coupon_public_status.unavailable")
        },
        code: code,
        loggedIn: logged_in?,
        applyUrl: logged_in? ? apply_store_coupon_path(code: code) : nil
      }
    end

    def apply
      require_login
      if apply_code_rate_limited?
        return redirect_to store_cart_path, alert: t("mcweb.flash.rate_limited", default: "操作过于频繁，请稍后再试。")
      end

      code = params[:code].to_s.strip.upcase
      cart = Commerce::Cart.find_by(user: current_user) ||
             Commerce::Cart.find_by(session_token: cookies.signed[:cart_token])
      cart_items = cart&.items&.includes(:product) || []
      subtotal_cents = cart_items.sum(&:total_cents)

      result = Commerce::PreviewCoupon.call(
        subtotal_cents: subtotal_cents,
        code: code,
        cart_items: cart_items,
        user: current_user
      )

      if result.success?
        session[:pending_coupon_code] = result.value[:code]
        redirect_to store_cart_path, notice: t("mcweb.flash.coupon_updated")
      else
        redirect_to store_cart_path, alert: service_error_message(result)
      end
    end
  end
end

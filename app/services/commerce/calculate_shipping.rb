# frozen_string_literal: true

module Commerce
  class CalculateShipping < ApplicationService
    def initialize(subtotal_cents:, cart_items: nil, coupon: nil, shipping_method_code: nil)
      @subtotal_cents = subtotal_cents.to_i
      @cart_items = cart_items
      @coupon = coupon
      @shipping_method_code = shipping_method_code.presence || "standard"
    end

    def call
      unless cart_requires_shipping?
        return ServiceResult.success(
          shipping_cents: 0,
          free_shipping: true,
          free_shipping_min_cents: 0,
          flat_shipping_cents: 0,
          amount_remaining_cents: 0,
          no_shippable_items: true,
          shipping_method_code: @shipping_method_code,
          shipping_method_label: nil
        )
      end

      min_cents = SiteSetting.get("store.free_shipping_min_order_cents", "0").to_i
      method = Commerce::ShippingMethods.find(@shipping_method_code) || Commerce::ShippingMethods.list.first
      method_cents = method ? method["cents"].to_i : SiteSetting.get("store.flat_shipping_cents", "0").to_i
      flat_cents = method_cents
      free_by_threshold = min_cents.positive? && @subtotal_cents >= min_cents
      free_by_coupon = @coupon&.free_shipping?
      free = free_by_threshold || free_by_coupon
      shipping_cents = free ? 0 : flat_cents
      remaining_cents = if min_cents.positive? && !free
                          [ min_cents - @subtotal_cents, 0 ].max
      else
                          0
      end

      ServiceResult.success(
        shipping_cents: shipping_cents,
        free_shipping: free,
        free_shipping_min_cents: min_cents,
        flat_shipping_cents: flat_cents,
        amount_remaining_cents: remaining_cents,
        coupon_free_shipping: free_by_coupon,
        shipping_method_code: method&.dig("code") || @shipping_method_code,
        shipping_method_label: method&.dig("label")
      )
    end

    private

    def cart_requires_shipping?
      return true if @cart_items.blank?

      @cart_items.any? { |item| shippable_product?(item.product) }
    end

    def shippable_product?(product)
      product.requires_shipping? || product.product_type == "physical"
    end
  end
end

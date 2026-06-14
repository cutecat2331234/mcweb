# frozen_string_literal: true

module Commerce
  class CalculateShipping < ApplicationService
    def initialize(subtotal_cents:)
      @subtotal_cents = subtotal_cents.to_i
    end

    def call
      min_cents = SiteSetting.get("store.free_shipping_min_order_cents", "0").to_i
      flat_cents = SiteSetting.get("store.flat_shipping_cents", "0").to_i
      free = min_cents.positive? && @subtotal_cents >= min_cents
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
        amount_remaining_cents: remaining_cents
      )
    end
  end
end

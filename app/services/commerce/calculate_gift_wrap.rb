# frozen_string_literal: true

module Commerce
  class CalculateGiftWrap < ApplicationService
    def initialize(enabled:, cart_items: nil)
      @enabled = ActiveModel::Type::Boolean.new.cast(enabled)
      @cart_items = cart_items
    end

    def call
      unless @enabled && cart_requires_shipping?
        return ServiceResult.success(gift_wrap: false, gift_wrap_cents: 0)
      end

      cents = SiteSetting.get("store.gift_wrap_cents", "500").to_i
      ServiceResult.success(gift_wrap: cents.positive?, gift_wrap_cents: [ cents, 0 ].max)
    end

    private

    def cart_requires_shipping?
      return false if @cart_items.blank?

      @cart_items.any? { |item| item.product&.requires_shipping? || item.product&.product_type == "physical" }
    end
  end
end

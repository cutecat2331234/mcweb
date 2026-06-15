# frozen_string_literal: true

module Commerce
  class ValidateShippingAddress < ApplicationService
    REQUIRED_FIELDS = %w[name phone line1 city province].freeze

    def initialize(cart_items:, shipping_address:)
      @cart_items = cart_items
      @shipping_address = shipping_address.is_a?(Hash) ? shipping_address.stringify_keys : {}
    end

    def call
      return ServiceResult.success unless cart_requires_shipping?

      missing = REQUIRED_FIELDS.select { |field| @shipping_address[field].to_s.strip.blank? }
      if missing.any?
        labels = { "name" => "收件人", "phone" => "手机号", "line1" => "地址", "city" => "城市", "province" => "省/州" }
        return ServiceResult.failure(error: "请填写收货地址：#{missing.map { |f| labels[f] }.join('、')}。")
      end

      ServiceResult.success
    end

    private

    def cart_requires_shipping?
      @cart_items.any? do |item|
        product = item.respond_to?(:product) ? item.product : item
        product&.requires_shipping?
      end
    end
  end
end

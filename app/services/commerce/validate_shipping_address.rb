# frozen_string_literal: true

module Commerce
  class ValidateShippingAddress < ApplicationService
    REQUIRED_FIELDS = %w[name phone line1 city province].freeze

    def initialize(cart_items:, shipping_address:)
      @cart_items = cart_items
      @shipping_address = shipping_address.is_a?(Hash) ? shipping_address.stringify_keys : {}
    end

    def call
      return ServiceResult.success unless Commerce::StoreFeatures.enabled?(:shipping)
      return ServiceResult.success unless cart_requires_shipping?

      missing = REQUIRED_FIELDS.select { |field| @shipping_address[field].to_s.strip.blank? }
      if missing.any?
        labels = REQUIRED_FIELDS.index_with { |field| I18n.t("commerce.shipping.address_fields.#{field}") }
        return ServiceResult.failure(
          error: I18n.t(
            "mcweb.services.errors.shipping_address_incomplete",
            fields: missing.map { |field| labels[field] }.join(I18n.t("support.array.words_connector"))
          )
        )
      end

      ServiceResult.success
    end

    private

    def cart_requires_shipping?
      @cart_items.any? do |item|
        product = item.respond_to?(:product) ? item.product : item
        shippable_product?(product)
      end
    end

    def shippable_product?(product)
      return false unless product

      if product.respond_to?(:requires_shipping?)
        product.requires_shipping?
      else
        product.try(:requires_shipping) == true || product.try(:product_type).to_s == "physical"
      end
    end
  end
end

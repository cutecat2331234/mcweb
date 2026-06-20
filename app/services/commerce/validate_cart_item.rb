# frozen_string_literal: true

module Commerce
  class ValidateCartItem < ApplicationService
    def initialize(user:, product:, variant: nil, quantity: 1, cart: nil, replace_quantity: false)
      @user = user
      @product = product
      @variant = variant
      @cart = cart
      @replace_quantity = replace_quantity
      @quantity = quantity.to_i
    end

    def call
      feature_error = validate_store_features!
      return feature_error if feature_error

      @quantity = resolved_quantity
      min_qty = [ @product.minimum_quantity.to_i, 1 ].max
      return ServiceResult.failure(error: I18n.t("commerce.cart.min_quantity", count: min_qty)) if @quantity < min_qty
      if @product.maximum_quantity.present? && @quantity > @product.maximum_quantity
        return ServiceResult.failure(error: I18n.t("commerce.cart.max_quantity", count: @product.maximum_quantity))
      end
      return ServiceResult.failure(error: I18n.t("commerce.cart.quantity_at_least_one")) if @quantity < 1
      return ServiceResult.failure(error: I18n.t("commerce.cart.product_inactive")) unless @product.active?

      if @product.variants.exists? && @variant.nil?
        return ServiceResult.failure(error: I18n.t("commerce.cart.variant_required"))
      end

      purchasable = @variant || @product
      if purchasable.stock.present? && purchasable.stock < @quantity
        return ServiceResult.failure(error: I18n.t("commerce.cart.out_of_stock")) unless @product.allow_backorder?
      end

      if @product.purchase_limit.present? && @user
        purchased = Commerce::OrderItem
          .joins(:order)
          .where(store_orders: { user_id: @user.id })
          .where.not(store_orders: { status: %w[cancelled failed refunded] })
          .where(store_product_id: @product.id)
          .sum(:quantity)

        if purchased + @quantity > @product.purchase_limit
          return ServiceResult.failure(error: I18n.t("commerce.cart.purchase_limit_exceeded"))
        end
      end

      cart_limit = SiteSetting.get("store.cart_max_items", "0").to_i
      if cart_limit.positive? && @cart
        other_qty = @cart.items.where.not(store_product_id: @product.id).sum(:quantity)
        line_qty = if @replace_quantity
                     @quantity
        else
                     existing = @cart.items.find_by(store_product_id: @product.id, store_product_variant_id: @variant&.id)
                     (existing&.quantity || 0) + @quantity
        end
        if other_qty + line_qty > cart_limit
          return ServiceResult.failure(error: I18n.t("commerce.cart.cart_max_items", count: cart_limit))
        end
      end

      prereq_result = Commerce::CheckProductPrerequisites.call(user: @user, product: @product)
      return prereq_result if prereq_result.failure?

      ServiceResult.success
    end

    private

    def validate_store_features!
      if @product.product_type == "physical" && !Commerce::StoreFeatures.enabled?(:physical_products)
        return ServiceResult.failure(error: I18n.t("commerce.cart.physical_products_disabled"))
      end

      if @product.requires_shipping? && !Commerce::StoreFeatures.enabled?(:shipping)
        return ServiceResult.failure(error: I18n.t("commerce.cart.shipping_disabled"))
      end

      nil
    end

    def resolved_quantity
      return @quantity if @replace_quantity || @cart.nil?

      existing = @cart.items.find_by(
        store_product_id: @product.id,
        store_product_variant_id: @variant&.id
      )
      (existing&.quantity || 0) + @quantity
    end
  end
end

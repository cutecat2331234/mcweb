# frozen_string_literal: true

module Commerce
  class CreateOrder < ApplicationService
    def initialize(cart:, user:, notes: nil, coupon_code: nil, gift_card_code: nil, use_store_credit: true, shipping_address: nil, shipping_method: nil, gift_wrap: false)
      @cart = cart
      @user = user
      @notes = notes
      @coupon_code = coupon_code
      @gift_card_code = gift_card_code
      @use_store_credit = ActiveModel::Type::Boolean.new.cast(use_store_credit)
      @shipping_address = shipping_address
      @shipping_method = shipping_method.presence || "standard"
      @gift_wrap = gift_wrap
    end

    def call
      return ServiceResult.failure(error: "cart_empty") if @cart.items.empty?
      unless @cart.user_id.nil? || @cart.user_id == @user.id
        return ServiceResult.failure(error: "cart_unauthorized")
      end

      cart_feature_error = validate_cart_store_features!
      return cart_feature_error if cart_feature_error

      @cart.items.includes(:product, :variant).find_each do |item|
        validation = Commerce::ValidateCartItem.call(
          user: @user,
          product: item.product,
          variant: item.variant,
          quantity: item.quantity
        )
        return validation if validation.failure?
      end

      address_result = Commerce::ValidateShippingAddress.call(
        cart_items: @cart.items.includes(:product),
        shipping_address: @shipping_address
      )
      return address_result if address_result.failure?

      subtotal_preview = @cart.items.includes(:product, :variant).sum { |item| item.total_cents }
      min_cents = SiteSetting.get("store.min_checkout_subtotal_cents", "0").to_i
      if min_cents.positive? && subtotal_preview < min_cents
        return ServiceResult.failure(
          error: I18n.t("mcweb.services.errors.order_min_subtotal_not_met", amount: min_cents / 100.0)
        )
      end

      order = nil
      coupon_error = nil
      empty_cart = false

      Commerce::Order.transaction do
        @cart.lock!
        if @cart.items.reload.empty?
          empty_cart = true
          raise ActiveRecord::Rollback
        end

        subtotal_cents = 0

        order = Commerce::Order.create!(
          public_id: generate_public_id,
          order_number: generate_order_number,
          user: @user,
          status: "pending",
          currency: "CNY",
          notes: @notes,
          shipping_address: normalized_shipping_address,
          shipping_method: effective_shipping_method
        )

        @cart.items.includes(:product, :variant).find_each do |item|
          product = item.product
          variant = item.variant
          unit_price_cents = variant&.price_cents || product.price_cents
          line_total = unit_price_cents * item.quantity
          subtotal_cents += line_total

          Commerce::OrderItem.create!(
            order: order,
            product: product,
            variant: variant,
            product_name: product.name,
            variant_name: variant&.name,
            unit_price_cents: unit_price_cents,
            quantity: item.quantity,
            total_cents: line_total,
            fulfillment_snapshot: snapshot_fulfillment(product, variant).merge(
              gift_note: item.gift_note.to_s.presence
            ).compact
          )

          stock_result = decrement_stock!(product, variant, item.quantity)
          if stock_result&.failure?
            coupon_error = stock_result.error
            raise ActiveRecord::Rollback
          end
        end

        cart_items = @cart.items.includes(:product)
        shipping_cents = shipping_cents_for(subtotal_cents, cart_items: cart_items)
        wrap_result = Commerce::CalculateGiftWrap.call(enabled: effective_gift_wrap, cart_items: cart_items)
        gift_wrap = wrap_result.success? && wrap_result.value[:gift_wrap]
        gift_wrap_cents = wrap_result.success? ? wrap_result.value[:gift_wrap_cents].to_i : 0

        order.update!(
          subtotal_cents: subtotal_cents,
          shipping_cents: shipping_cents,
          gift_wrap: gift_wrap,
          gift_wrap_cents: gift_wrap_cents,
          total_cents: subtotal_cents + shipping_cents + gift_wrap_cents,
          discount_cents: 0
        )

        if @coupon_code.present?
          coupon_result = Commerce::ApplyCoupon.call(order: order, code: @coupon_code)
          unless coupon_result.success?
            coupon_error = coupon_result.error
            raise ActiveRecord::Rollback
          end
        end

        if @gift_card_code.present?
          gift_result = Commerce::ApplyGiftCard.call(order: order, code: @gift_card_code)
          unless gift_result.success?
            coupon_error = gift_result.error
            raise ActiveRecord::Rollback
          end
        end

        if @use_store_credit
          credit_result = Commerce::ApplyStoreCredit.call(order: order, user: @user)
          unless credit_result.success?
            coupon_error = credit_result.error
            raise ActiveRecord::Rollback
          end
        end

        @cart.items.destroy_all
      end

      return ServiceResult.failure(error: coupon_error) if coupon_error.present?
      return ServiceResult.failure(error: "cart_empty") if empty_cart
      return ServiceResult.failure(error: "cannot_create_order") unless order&.persisted?

      Commerce::OrderEvent.create!(
        order: order,
        event_type: "created",
        to_status: "pending",
        actor: @user
      )

      Administration::AuditLogger.call(
        actor: @user,
        action: "commerce.order_created",
        resource: order
      )

      MailDeliveryJob.perform_later("Commerce::OrderMailer", "order_created", "deliver_now", args: [ order.id ])
      Commerce::InAppNotification.order_event(
        user: order.user,
        notification_type: "commerce.order_created",
        key: "order_created",
        order: order
      )

      Commerce::DispatchOrderWebhook.call(
        order: order,
        event_type: "order.created",
        from_status: nil,
        to_status: "pending"
      )

      ServiceResult.success(order)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def decrement_stock!(product, variant, quantity)
      target = variant || product
      return ServiceResult.success if target.stock.nil?

      target.with_lock do
        if target.stock < quantity && !product.allow_backorder?
          return ServiceResult.failure(error: "stock_insufficient")
        end

        # Decrement by the full quantity even past zero for backorders. The negative
        # value records the oversold count and keeps decrement/restore symmetric, so a
        # later refund or cancel cannot create phantom inventory (capping at 0 did).
        target.update!(stock: target.stock - quantity)
      end

      ServiceResult.success
    end

    def snapshot_fulfillment(product, variant)
      config = variant&.fulfillment_config.presence || product.fulfillment_config
      snapshot = {
        product_id: product.id,
        product_public_id: product.public_id,
        variant_id: variant&.id,
        product_type: product.product_type,
        fulfillment_config: config
      }
      snapshot[:membership_type_id] = product.store_membership_type_id if product.membership_product?
      snapshot
    end

    def generate_public_id
      "ord_#{SecureRandom.alphanumeric(16)}"
    end

    def generate_order_number
      "MC#{Time.current.strftime('%Y%m%d')}#{SecureRandom.hex(4).upcase}"
    end

    def shipping_cents_for(subtotal_cents, cart_items: nil, coupon: nil)
      result = Commerce::CalculateShipping.call(
        subtotal_cents: subtotal_cents,
        cart_items: cart_items,
        coupon: coupon,
        shipping_method_code: effective_shipping_method
      )
      result.success? ? result.value[:shipping_cents].to_i : 0
    end

    def effective_shipping_method
      return nil unless Commerce::StoreFeatures.enabled?(:shipping)

      @shipping_method
    end

    def effective_gift_wrap
      Commerce::StoreFeatures.enabled?(:gift_wrap) && ActiveModel::Type::Boolean.new.cast(@gift_wrap)
    end

    def validate_cart_store_features!
      @cart.items.includes(:product).find_each do |item|
        product = item.product
        next unless product

        unless Commerce::StoreFeatures.product_visible?(product)
          return ServiceResult.failure(error: I18n.t("commerce.cart.unsupported_feature_product"))
        end
      end
      nil
    end

    def normalized_shipping_address
      return {} unless Commerce::StoreFeatures.enabled?(:shipping)
      return {} unless @shipping_address.is_a?(Hash)

      {
        "name" => @shipping_address["name"].to_s.strip.presence,
        "phone" => @shipping_address["phone"].to_s.strip.presence,
        "line1" => @shipping_address["line1"].to_s.strip.presence,
        "line2" => @shipping_address["line2"].to_s.strip.presence,
        "city" => @shipping_address["city"].to_s.strip.presence,
        "province" => @shipping_address["province"].to_s.strip.presence,
        "postal_code" => @shipping_address["postal_code"].to_s.strip.presence
      }.compact
    end
  end
end

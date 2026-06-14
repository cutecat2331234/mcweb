# frozen_string_literal: true

module Commerce
  class CreateOrder < ApplicationService
    def initialize(cart:, user:, notes: nil, coupon_code: nil, gift_card_code: nil)
      @cart = cart
      @user = user
      @notes = notes
      @coupon_code = coupon_code
      @gift_card_code = gift_card_code
    end

    def call
      return ServiceResult.failure(error: "购物车为空。") if @cart.items.empty?

      @cart.items.includes(:product, :variant).find_each do |item|
        validation = Commerce::ValidateCartItem.call(
          user: @user,
          product: item.product,
          variant: item.variant,
          quantity: item.quantity
        )
        return validation if validation.failure?
      end

      order = nil
      coupon_error = nil

      Commerce::Order.transaction do
        subtotal_cents = 0

        order = Commerce::Order.create!(
          public_id: generate_public_id,
          order_number: generate_order_number,
          user: @user,
          status: "pending",
          currency: "CNY",
          notes: @notes
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
            fulfillment_snapshot: snapshot_fulfillment(product, variant)
          )

          stock_result = decrement_stock!(product, variant, item.quantity)
          if stock_result&.failure?
            coupon_error = stock_result.error
            raise ActiveRecord::Rollback
          end
        end

        order.update!(
          subtotal_cents: subtotal_cents,
          shipping_cents: shipping_cents_for(subtotal_cents),
          total_cents: subtotal_cents + shipping_cents_for(subtotal_cents),
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

        @cart.items.destroy_all
      end

      return ServiceResult.failure(error: coupon_error) if coupon_error.present?
      return ServiceResult.failure(error: "无法创建订单。") unless order&.persisted?

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
      Commerce::NotifyOrderEvent.call(
        user: order.user,
        notification_type: "commerce.order_created",
        title: "订单已创建",
        body: "订单 #{order.order_number} 等待支付。",
        path: "/store/orders/#{order.public_id}"
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
        if target.stock < quantity
          if product.allow_backorder?
            target.update!(stock: 0)
            return ServiceResult.success
          end

          return ServiceResult.failure(error: "库存不足。")
        end

        target.update!(stock: target.stock - quantity)
      end

      ServiceResult.success
    end

    def snapshot_fulfillment(product, variant)
      config = variant&.fulfillment_config.presence || product.fulfillment_config
      {
        product_id: product.id,
        product_public_id: product.public_id,
        variant_id: variant&.id,
        product_type: product.product_type,
        fulfillment_config: config
      }
    end

    def generate_public_id
      "ord_#{SecureRandom.alphanumeric(16)}"
    end

    def generate_order_number
      "MC#{Time.current.strftime('%Y%m%d')}#{SecureRandom.hex(4).upcase}"
    end

    def shipping_cents_for(subtotal_cents)
      result = Commerce::CalculateShipping.call(subtotal_cents: subtotal_cents)
      result.success? ? result.value[:shipping_cents].to_i : 0
    end
  end
end

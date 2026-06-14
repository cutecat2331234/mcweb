# frozen_string_literal: true

module Commerce
  class CreateOrder < ApplicationService
    def initialize(cart:, user:, notes: nil)
      @cart = cart
      @user = user
      @notes = notes
    end

    def call
      return ServiceResult.failure(error: "Cart is empty.") if @cart.items.empty?

      order = nil
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
        end

        order.update!(
          subtotal_cents: subtotal_cents,
          total_cents: subtotal_cents,
          discount_cents: 0
        )

        @cart.items.destroy_all
      end

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

      ServiceResult.success(order)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

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
  end
end

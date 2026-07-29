# frozen_string_literal: true

require_relative "normalizer"

module Mcweb
  module PluginApi
    module V1
      # Explicit allow-list serializers for payment-domain resources. Customer
      # identity, addresses, notes, provider references, metadata and approval
      # actors intentionally never cross the plugin boundary.
      module CommerceSnapshot
        SCHEMA_VERSION = "1"

        module_function

        def category(category)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "commerce.category",
            id: category.id,
            name: category.name,
            slug: category.slug,
            position: category.position,
            created_at: category.created_at,
            updated_at: category.updated_at
          )
        end

        def product(product)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "commerce.product",
            id: product.id,
            public_id: product.public_id,
            category: product.category && {
              id: product.category.id,
              name: product.category.name,
              slug: product.category.slug
            },
            name: product.name,
            slug: product.slug,
            summary: product.summary,
            product_type: product.product_type,
            status: product.status,
            featured: product.featured?,
            price_cents: product.price_cents,
            compare_at_price_cents: product.compare_at_price_cents,
            currency: product.currency,
            minimum_quantity: product.minimum_quantity,
            maximum_quantity: product.maximum_quantity,
            available_at: product.available_at,
            unavailable_at: product.unavailable_at,
            availability: availability_fields(product),
            variants: product.variants.sort_by(&:id).map { |variant| variant_fields(variant) },
            created_at: product.created_at,
            updated_at: product.updated_at
          )
        end

        def pricing(product)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "commerce.pricing",
            product_public_id: product.public_id,
            currency: product.currency,
            price_cents: product.price_cents,
            compare_at_price_cents: product.compare_at_price_cents,
            on_sale: product.on_sale?,
            variants: product.variants.sort_by(&:id).map do |variant|
              {
                id: variant.id,
                name: variant.name,
                sku: variant.sku,
                price_cents: variant.price_cents,
                compare_at_price_cents: variant.compare_at_price_cents,
                on_sale: variant.on_sale?
              }
            end,
            updated_at: product.updated_at
          )
        end

        def availability(product)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "commerce.availability",
            product_public_id: product.public_id,
            **availability_fields(product),
            variants: product.variants.sort_by(&:id).map do |variant|
              {
                id: variant.id,
                sku: variant.sku,
                in_stock: variant.in_stock?,
                unlimited: variant.stock.nil?,
                purchasable: product.available? &&
                  (variant.in_stock? || product.allow_backorder?)
              }
            end,
            updated_at: product.updated_at
          )
        end

        def inventory(target, reserved_quantity:)
          product = target.is_a?(::Commerce::Product) ? target : target.product
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "commerce.inventory",
            target_type: target.is_a?(::Commerce::Product) ? "product" : "variant",
            target_id: target.is_a?(::Commerce::Product) ? target.public_id : target.id.to_s,
            product_public_id: product.public_id,
            variant_id: target.is_a?(::Commerce::ProductVariant) ? target.id : nil,
            sku: target.respond_to?(:sku) ? target.sku : nil,
            unlimited: target.stock.nil?,
            available_quantity: target.stock,
            reserved_quantity: reserved_quantity,
            in_stock: target.in_stock?,
            allow_backorder: product.allow_backorder?,
            purchasable: product.available? &&
              (target.in_stock? || product.allow_backorder?),
            updated_at: target.updated_at
          )
        end

        def order(order)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "commerce.order_status",
            id: order.id,
            public_id: order.public_id,
            status: order.status,
            total_cents: order.total_cents,
            currency: order.currency,
            created_at: order.created_at,
            updated_at: order.updated_at
          )
        end

        def payment(payment, order:)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "commerce.payment_status",
            id: payment.id,
            order_public_id: order.public_id,
            status: payment.status,
            amount_cents: payment.amount_cents,
            currency: payment.currency,
            created_at: payment.created_at,
            updated_at: payment.updated_at
          )
        end

        def refund(refund, order:)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "commerce.refund_status",
            id: refund.id,
            order_public_id: order.public_id,
            status: refund.status,
            amount_cents: refund.amount_cents,
            currency: order.currency,
            created_at: refund.created_at,
            updated_at: refund.updated_at
          )
        end

        def fulfillment(fulfillment)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "commerce.fulfillment_status",
            id: fulfillment.id,
            delivery_id: fulfillment.delivery_id,
            order_public_id: fulfillment.order.public_id,
            order_item_id: fulfillment.order_item.id,
            product_name: fulfillment.order_item.product_name,
            status: fulfillment.status,
            attempts_count: fulfillment.attempts_count,
            max_attempts: fulfillment.max_attempts,
            retryable: fulfillment.retryable?,
            cancellable: fulfillment.pending? || fulfillment.processing? || fulfillment.failed?,
            next_attempt_at: fulfillment.next_attempt_at,
            fulfilled_at: fulfillment.fulfilled_at,
            cancelled_at: fulfillment.cancelled_at,
            created_at: fulfillment.created_at,
            updated_at: fulfillment.updated_at
          )
        end

        def authorization(value, operation:, targets:)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "commerce.action_authorization",
            operation: operation,
            action: value.fetch(:action),
            request_uuid: value.fetch(:request_id),
            authorization_token: value.fetch(:authorization_token),
            confirmation: value.fetch(:confirmation),
            expires_in: value.fetch(:expires_in),
            targets: targets
          )
        end

        def order_action(value, action:)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "commerce.order_action",
            action: action,
            request_uuid: value.fetch(:request_id),
            idempotent: value.fetch(:idempotent),
            processed: value.fetch(:processed),
            orders: Array(value.fetch(:orders)).map { |record| order(record) }
          )
        end

        def inventory_adjustment(value, target:)
          movement = value.fetch(:movement)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "commerce.inventory_adjustment",
            request_uuid: movement.request_id,
            idempotent: value.fetch(:idempotent),
            movement_public_id: movement.public_id,
            delta: movement.available_delta,
            balance: value.fetch(:balance),
            target: inventory(
              target,
              reserved_quantity: active_reservations(target)
            )
          )
        end

        def fulfillment_action(value)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "commerce.fulfillment_action",
            action: value.fetch(:action),
            request_uuid: value.fetch(:attempt).request_id,
            idempotent: value.fetch(:idempotent),
            fulfillment: fulfillment(value.fetch(:fulfillment))
          )
        end

        def refund_request(record, request_uuid:, idempotent:)
          Normalizer.call(
            schema_version: SCHEMA_VERSION,
            type: "commerce.refund_request",
            request_uuid: request_uuid,
            idempotent: idempotent,
            refund: refund(record, order: record.order)
          )
        end

        def availability_fields(product)
          {
            available: product.available?,
            in_stock: product.in_stock?,
            backorder_available: product.backorder_available?,
            purchasable: product.available? && product.purchasable?
          }
        end
        private_class_method :availability_fields

        def variant_fields(variant)
          {
            id: variant.id,
            name: variant.name,
            sku: variant.sku,
            price_cents: variant.price_cents,
            compare_at_price_cents: variant.compare_at_price_cents,
            in_stock: variant.in_stock?,
            unlimited: variant.stock.nil?
          }
        end
        private_class_method :variant_fields

        def active_reservations(target)
          ::Commerce::InventoryReservation.active.where(target: target).sum(:quantity)
        end
        private_class_method :active_reservations
      end
    end
  end
end

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
      end
    end
  end
end

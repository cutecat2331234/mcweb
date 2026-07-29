# frozen_string_literal: true

module Commerce
  # Stable, privacy-preserving event snapshots for commerce plugins.
  #
  # Every builder below is an explicit allow-list. Provider references,
  # provider/customer metadata, addresses, usernames, email addresses, free-form
  # reasons, and raw connector responses must never be added to these payloads.
  module DomainEvents
    EVENTS = %w[
      commerce.order.paid
      commerce.payment.confirmed
      commerce.payment.failed
      commerce.payment.refunded
      commerce.refund.requested
      commerce.refund.processed
      commerce.refund.rejected
      commerce.inventory.reserved
      commerce.inventory.released
      commerce.inventory.confirmed
      commerce.inventory.adjusted
      commerce.fulfillment.dispatched
      commerce.fulfillment.retryable_failed
      commerce.fulfillment.failed
      commerce.fulfillment.completed
      commerce.fulfillment.cancelled
    ].freeze

    module_function

    def publish_after_commit(event, payload)
      name = event.to_s
      raise ArgumentError, "unknown commerce event #{name.inspect}" unless EVENTS.include?(name)

      snapshot = deep_freeze(payload.deep_dup)
      ActiveRecord.after_all_transactions_commit do
        Mcweb::Events.defer_until_success do
          Mcweb::Events.publish(name, snapshot)
        end
      end
      true
    end

    def order_paid(order)
      { order: order_snapshot(order) }
    end

    def payment(payment)
      {
        payment: {
          id: payment.id,
          status: payment.status,
          amount_cents: payment.amount_cents,
          currency: payment.currency
        },
        order: order_snapshot(payment.order)
      }
    end

    def refund(refund)
      {
        refund: {
          id: refund.id,
          status: refund.status,
          amount_cents: refund.amount_cents,
          currency: refund.order.currency
        },
        payment: {
          id: refund.payment_record_id,
          status: refund.payment_record.status,
          amount_cents: refund.payment_record.amount_cents,
          currency: refund.payment_record.currency
        },
        order: order_snapshot(refund.order)
      }
    end

    def inventory(movement)
      target = movement.target
      product = target.is_a?(Commerce::Product) ? target : target.product
      {
        inventory: {
          target_type: target.is_a?(Commerce::Product) ? "product" : "variant",
          target_id: target.is_a?(Commerce::Product) ? target.public_id : target.id.to_s,
          product_public_id: product.public_id,
          variant_id: target.is_a?(Commerce::ProductVariant) ? target.id : nil,
          available_quantity: movement.available_after,
          reserved_quantity: movement.reserved_after,
          sold_quantity: movement.sold_after
        },
        movement: {
          public_id: movement.public_id,
          type: movement.movement_type,
          quantity: movement.quantity,
          available_delta: movement.available_delta,
          reserved_delta: movement.reserved_delta,
          sold_delta: movement.sold_delta
        },
        order: movement.order && order_snapshot(movement.order)
      }.compact
    end

    def fulfillment(fulfillment, attempt: nil, result: nil)
      payload = {
        fulfillment: {
          id: fulfillment.id,
          delivery_id: fulfillment.delivery_id,
          order_item_id: fulfillment.store_order_item_id,
          status: fulfillment.status,
          attempts_count: fulfillment.attempts_count,
          max_attempts: fulfillment.max_attempts,
          retryable: fulfillment.retryable?,
          next_attempt_at: fulfillment.next_attempt_at,
          fulfilled_at: fulfillment.fulfilled_at,
          cancelled_at: fulfillment.cancelled_at
        },
        order: order_snapshot(fulfillment.order)
      }
      if attempt
        payload[:attempt] = {
          number: attempt.attempt_number,
          trigger: attempt.trigger,
          status: attempt.status
        }
      end
      if result
        payload[:result] = Commerce::Fulfillment.safe_result_summary(result)
      end
      payload
    end

    def order_snapshot(order)
      {
        public_id: order.public_id,
        status: order.status,
        total_cents: order.total_cents,
        currency: order.currency
      }
    end
    private_class_method :order_snapshot

    def deep_freeze(value)
      case value
      when Hash
        value.each do |key, entry|
          deep_freeze(key)
          deep_freeze(entry)
        end
      when Array
        value.each { |entry| deep_freeze(entry) }
      end
      value.freeze
    end
    private_class_method :deep_freeze
  end
end

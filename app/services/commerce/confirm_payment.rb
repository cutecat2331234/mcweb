# frozen_string_literal: true

module Commerce
  class ConfirmPayment < ApplicationService
    ORPHAN_REASONS = %w[
      order_cancelled
      order_expired
      order_already_paid
      order_not_payable
      payment_superseded
    ].freeze
    APPLIED_PAYMENT_STATUSES = %w[paid processing fulfilling fulfilled completed refunded].freeze

    def initialize(payment_record:, provider_payment_id: nil, metadata: {}, webhook_event: nil)
      @payment_record = payment_record
      @provider_payment_id = provider_payment_id
      @metadata = metadata
      @webhook_event = webhook_event
    end

    def call
      newly_paid = false
      order_id = nil
      payment_error = nil
      orphan_reason = nil
      late_payment_case = nil
      from_status = nil
      idempotent_succeeded = false

      Commerce::Order.transaction do
        order = Commerce::Order.lock.find(@payment_record.store_order_id)
        record = order.payment_records.lock.find(@payment_record.id)
        order_id = order.id

        if record.succeeded?
          existing_reason = record.metadata["orphan_reason"].to_s
          if record.metadata["orphaned"] == true && existing_reason.in?(ORPHAN_REASONS)
            orphan_reason = existing_reason
            payment_error = orphan_error(orphan_reason)
            late_payment_case = enqueue_late_payment_case!(record, orphan_reason)
          elsif applied_to_order?(order, record) || !order_has_applied_payment?(order)
            idempotent_succeeded = true
          else
            orphan_reason = "order_already_paid"
            payment_error = orphan_error(orphan_reason)
            late_payment_case = persist_orphaned_payment!(record, orphan_reason)
          end
        elsif !record.pending? && !record.processing?
          if @webhook_event
            orphan_reason = orphan_reason_for(order, superseded: true)
            payment_error = orphan_error(orphan_reason)
            late_payment_case = persist_orphaned_payment!(record, orphan_reason)
          else
            payment_error = "Payment is no longer valid."
          end
        elsif !order.payable?
          orphan_reason = orphan_reason_for(order)
          payment_error = order.payment_expired? ? "order_payment_expired" : "order_not_payable"
          late_payment_case = persist_orphaned_payment!(record, orphan_reason)
        elsif record.amount_cents != order.total_cents
          payment_error = "payment_amount_mismatch"
        else
          if order.gift_card_amount_cents.to_i.positive?
            debit_result = Commerce::DebitGiftCard.call(order: order)
            unless debit_result.success?
              payment_error = debit_result.error || "gift_card_debit_failed"
              raise ActiveRecord::Rollback
            end
          end

          if order.store_credit_amount_cents.to_i.positive?
            credit_result = Commerce::DebitStoreCredit.call(order: order)
            unless credit_result.success?
              payment_error = credit_result.error || "store_credit_debit_failed"
              raise ActiveRecord::Rollback
            end
          end

          from_status = order.status
          order.submit_payment! if order.pending? && order.may_submit_payment?
          order.mark_paid! if order.awaiting_payment? && order.may_mark_paid?

          unless order.paid?
            payment_error = "order_cannot_mark_paid"
            raise ActiveRecord::Rollback
          end

          inventory_result = Commerce::ConfirmInventoryReservations.call(order: order)
          unless inventory_result.success?
            payment_error = inventory_result.error || "inventory_reservation_invalid"
            raise ActiveRecord::Rollback
          end

          Commerce::OrderEvent.create!(
            order: order,
            event_type: "payment_confirmed",
            from_status: from_status,
            to_status: "paid",
            metadata: { payment_record_id: record.id }
          )
          newly_paid = true

          record.update!(
            status: "succeeded",
            provider_payment_id: @provider_payment_id || record.provider_payment_id,
            metadata: record.metadata.merge(@metadata)
          )
          Commerce::DomainEvents.publish_after_commit(
            "commerce.payment.confirmed",
            Commerce::DomainEvents.payment(record)
          )
        end
      end

      if payment_error.present?
        return ServiceResult.failure(
          error: payment_error,
          value: {
            orphaned: orphan_reason.present?,
            late_payment_case: late_payment_case
          }
        )
      end

      if idempotent_succeeded
        resume_payment_completion!
        return ServiceResult.success(record: @payment_record.reload, idempotent: true, newly_paid: false)
      end

      if newly_paid && order_id
        order = Commerce::Order.find(order_id)
        completion = Commerce::CompleteOrderPayment.call(order: order, from_status: from_status)
        return completion unless completion.success?
      end

      ServiceResult.success(record: @payment_record.reload, idempotent: false, newly_paid: newly_paid)
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    end

    private

    def orphan_reason_for(order, superseded: false)
      return "order_cancelled" if order.cancelled?
      return "order_expired" if order.payment_expired?
      return "order_already_paid" if order_has_applied_payment?(order)
      return "payment_superseded" if superseded

      "order_not_payable"
    end

    def orphan_error(reason)
      return "order_payment_expired" if reason == "order_expired"
      return "Payment is no longer valid." if reason == "payment_superseded"

      "order_not_payable"
    end

    def persist_orphaned_payment!(record, reason)
      record.update!(
        status: "succeeded",
        provider_payment_id: @provider_payment_id || record.provider_payment_id,
        metadata: record.metadata.merge(
          @metadata.stringify_keys
        ).merge(
          "orphaned" => true,
          "orphan_reason" => reason,
          "requires_manual_review" => true
        )
      )

      late_payment_case = enqueue_late_payment_case!(record, reason)
      Rails.logger.warn(
        "[ConfirmPayment] Orphaned payment recorded: payment_record=#{record.id} reason=#{reason}"
      )
      late_payment_case
    end

    def enqueue_late_payment_case!(record, reason)
      return unless @webhook_event

      Payments::LatePaymentCase.enqueue_from_verified_webhook!(
        payment_record: record,
        webhook_event: @webhook_event,
        reason: reason
      )
    end

    def applied_to_order?(order, record)
      order.events
        .where(event_type: "payment_confirmed")
        .where("metadata ->> 'payment_record_id' = ?", record.id.to_s)
        .exists?
    end

    def order_has_applied_payment?(order)
      APPLIED_PAYMENT_STATUSES.include?(order.status) ||
        order.events.where(event_type: "payment_confirmed").exists?
    end

    def resume_payment_completion!
      order = Commerce::Order.find_by(id: @payment_record.store_order_id)
      return unless order&.paid?

      Commerce::CompleteOrderPayment.call(order: order, from_status: order.status)
    end
  end
end

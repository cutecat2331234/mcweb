# frozen_string_literal: true

module Commerce
  class ConfirmPayment < ApplicationService
    ORPHAN_REASONS = %w[order_cancelled order_expired].freeze

    def initialize(payment_record:, provider_payment_id: nil, metadata: {})
      @payment_record = payment_record
      @provider_payment_id = provider_payment_id
      @metadata = metadata
    end

    def call
      newly_paid = false
      order_id = nil
      payment_error = nil
      orphan_reason = nil
      from_status = nil
      idempotent_succeeded = false

      Payments::Record.transaction do
        record = Payments::Record.lock.find(@payment_record.id)

        if record.status == "succeeded"
          idempotent_succeeded = true
        else
          unless %w[pending processing].include?(record.status)
            payment_error = "Payment is no longer valid."
            raise ActiveRecord::Rollback
          end

          order = Commerce::Order.lock.find(record.store_order_id)
          order_id = order.id

          unless order.payable?
            orphan_reason = orphan_reason_for(order)
            payment_error = order.payment_expired? ? "order_payment_expired" : "order_not_payable"
            raise ActiveRecord::Rollback
          end

          if record.amount_cents != order.total_cents
            payment_error = "payment_amount_mismatch"
            raise ActiveRecord::Rollback
          end

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
        end
      end

      if payment_error.present?
        record_orphaned_payment!(orphan_reason) if orphan_reason.present?
        return ServiceResult.failure(error: payment_error, value: { orphaned: orphan_reason.present? })
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
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def orphan_reason_for(order)
      return "order_cancelled" if order.cancelled?
      return "order_expired" if order.payment_expired?

      nil
    end

    def record_orphaned_payment!(reason)
      return unless ORPHAN_REASONS.include?(reason)

      Payments::Record.transaction do
        record = Payments::Record.lock.find(@payment_record.id)
        next unless record.pending? || record.processing?

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
      end

      Rails.logger.warn(
        "[ConfirmPayment] Orphaned payment recorded: payment_record=#{@payment_record.id} reason=#{reason}"
      )
    end

    def resume_payment_completion!
      order = Commerce::Order.find_by(id: @payment_record.store_order_id)
      return unless order&.paid?

      Commerce::CompleteOrderPayment.call(order: order, from_status: order.status)
    end
  end
end

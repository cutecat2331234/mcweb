# frozen_string_literal: true

module Commerce
  class PrepareOrderPayment < ApplicationService
    ACTIVE_STATUSES = %w[pending processing].freeze

    def initialize(order:, provider:, provider_mode: nil)
      @order = order
      @provider = provider.to_s
      @provider_mode = provider_mode.presence
    end

    def call
      payment_record = nil
      failure = nil

      Commerce::Order.transaction do
        order = Commerce::Order.lock.find(@order.id)

        unless order.payable?
          failure = order.payment_expired? ? "order_payment_expired" : "order_cannot_continue_payment"
          next
        end

        if order.pending? && order.may_submit_payment?
          order.submit_payment!
          unless order.awaiting_payment?
            failure = "order_cannot_continue_payment"
            next
          end
        elsif !order.awaiting_payment?
          failure = "order_cannot_continue_payment"
          next
        end

        active_records = order.payment_records
          .where(status: ACTIVE_STATUSES)
          .order(:id)
          .lock
          .to_a

        if active_records.many?
          failure = "multiple_active_payment_attempts_require_reconciliation"
          next
        end

        active_record = active_records.first
        if active_record
          if matching_attempt?(active_record, order)
            payment_record = active_record
          else
            failure = "payment_attempt_already_active"
          end
          next
        end

        payment_record = Payments::Record.create!(
          order: order,
          provider: @provider,
          provider_mode: @provider_mode,
          amount_cents: order.total_cents,
          currency: order.currency,
          status: :pending
        )
      end

      return ServiceResult.failure(error: failure) if failure

      ServiceResult.success(payment_record)
    rescue ActiveRecord::RecordNotUnique
      ServiceResult.failure(error: "payment_attempt_already_active")
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    end

    private

    def matching_attempt?(record, order)
      record.provider == @provider &&
        record.provider_mode == @provider_mode &&
        record.amount_cents == order.total_cents &&
        record.currency.to_s.casecmp?(order.currency.to_s)
    end
  end
end

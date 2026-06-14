# frozen_string_literal: true

module Commerce
  class ConfirmPayment < ApplicationService
    def initialize(payment_record:, provider_payment_id: nil, metadata: {})
      @payment_record = payment_record
      @provider_payment_id = provider_payment_id
      @metadata = metadata
    end

    def call
      Payments::Record.transaction do
        record = Payments::Record.lock.find(@payment_record.id)

        if record.status == "succeeded"
          return ServiceResult.success(record: record, idempotent: true)
        end

        record.update!(
          status: "succeeded",
          provider_payment_id: @provider_payment_id || record.provider_payment_id,
          metadata: record.metadata.merge(@metadata)
        )

        order = record.order
        if order.status == "pending"
          order.update!(status: "paid")
          Commerce::OrderEvent.create!(
            order: order,
            event_type: "payment_confirmed",
            from_status: "pending",
            to_status: "paid",
            metadata: { payment_record_id: record.id }
          )
        end

        ServiceResult.success(record: record, idempotent: false)
      end
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

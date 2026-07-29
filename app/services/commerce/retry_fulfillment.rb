# frozen_string_literal: true

module Commerce
  class RetryFulfillment < ApplicationService
    def initialize(fulfillment:)
      @fulfillment = fulfillment
    end

    def call
      Commerce::Fulfillment.transaction do
        @fulfillment.lock!
        return ServiceResult.failure(error: "fulfillment_not_retryable") unless @fulfillment.retryable?

        reservation = @fulfillment.order_item.inventory_reservation
        return ServiceResult.failure(error: "fulfillment_inventory_unavailable") if reservation && !reservation.confirmed?

        supersede_active_connector_tasks!
        @fulfillment.update!(
          status: "pending",
          last_error: nil,
          next_attempt_at: nil,
          cancelled_at: nil,
          cancel_reason: nil
        )
      end
      ActiveRecord.after_all_transactions_commit do
        Minecraft::EnsureInstanceRunningJob.perform_later(@fulfillment.id)
      end

      ServiceResult.success(@fulfillment)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def supersede_active_connector_tasks!
      Minecraft::ConnectorTask.where(fulfillment: @fulfillment, status: %w[pending claimed]).find_each do |task|
        task.fail!(error: "superseded_by_retry")
      end
    end
  end
end

# frozen_string_literal: true

module Commerce
  class RetryFulfillment < ApplicationService
    def initialize(fulfillment:)
      @fulfillment = fulfillment
    end

    def call
      unless @fulfillment.pending? || @fulfillment.failed?
        return ServiceResult.failure(error: "Fulfillment cannot be retried.")
      end

      order = @fulfillment.order
      if order.refunded? || order.cancelled?
        return ServiceResult.failure(error: "Order is no longer eligible for fulfillment.")
      end

      supersede_active_connector_tasks!

      @fulfillment.update!(status: "pending", last_error: nil)
      Minecraft::EnsureInstanceRunningJob.perform_later(@fulfillment.id)

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

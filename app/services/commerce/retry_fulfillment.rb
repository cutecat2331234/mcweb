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

      @fulfillment.update!(status: "pending", last_error: nil)
      Minecraft::DispatchFulfillmentJob.perform_later(@fulfillment.id)

      ServiceResult.success(@fulfillment)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

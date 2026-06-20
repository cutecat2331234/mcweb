# frozen_string_literal: true

module Community
  class BulkRetrySavedSearchWebhooks < ApplicationService
    def initialize(delivery_ids:)
      @delivery_ids = Array(delivery_ids).map(&:to_i).uniq
    end

    def call
      return ServiceResult.failure(error: "deliveries_not_selected") if @delivery_ids.empty?

      queued = 0
      Community::SavedSearchWebhookDelivery
        .where(id: @delivery_ids, status: "failed")
        .find_each do |delivery|
          result = Community::AdminRetrySavedSearchWebhook.call(delivery: delivery)
          queued += 1 if result.success?
        end

      ServiceResult.success(queued: queued)
    end
  end
end

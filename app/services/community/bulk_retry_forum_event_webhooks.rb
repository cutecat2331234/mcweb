# frozen_string_literal: true

module Community
  class BulkRetryForumEventWebhooks < ApplicationService
    def initialize(delivery_ids:)
      @delivery_ids = Array(delivery_ids).map(&:to_i).uniq.reject(&:zero?)
    end

    def call
      return ServiceResult.failure(error: "webhook_deliveries_not_selected") if @delivery_ids.empty?

      queued = 0
      Community::EventWebhookDelivery.where(id: @delivery_ids, status: "failed").find_each do |delivery|
        next if delivery.request_payload.blank?

        result = AdminRetryForumEventWebhook.call(delivery: delivery)
        queued += 1 if result.success?
      end

      ServiceResult.success(queued: queued)
    end
  end
end

# frozen_string_literal: true

module Commerce
  class BulkRetryOrderWebhooks < ApplicationService
    def initialize(delivery_ids:)
      @delivery_ids = Array(delivery_ids).map(&:to_i).uniq
    end

    def call
      return ServiceResult.failure(error: "未选择投递记录") if @delivery_ids.empty?

      queued = 0
      Commerce::OrderWebhookDelivery
        .where(id: @delivery_ids, status: "failed")
        .find_each do |delivery|
          result = Commerce::AdminRetryOrderWebhook.call(delivery: delivery)
          queued += 1 if result.success?
        end

      ServiceResult.success(queued: queued)
    end
  end
end

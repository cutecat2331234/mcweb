# frozen_string_literal: true

module Community
  class RetryFailedSavedSearchWebhooksJob < ApplicationJob
    queue_as :maintenance

    STALE_PENDING_AFTER = 5.minutes
    MAX_ATTEMPTS = Community::DispatchSavedSearchWebhookJob::MAX_ATTEMPTS

    def perform
      Community::SavedSearchWebhookDelivery
        .where(status: "pending")
        .where(created_at: ...STALE_PENDING_AFTER.ago)
        .find_each do |delivery|
          if delivery.attempt_count < MAX_ATTEMPTS && delivery.request_payload.present?
            requeue_delivery(delivery)
          else
            delivery.update!(
              status: "failed",
              response_body: "投递超时".truncate(4000)
            )
          end
        end
    end

  private

    def requeue_delivery(delivery)
      search = delivery.saved_search
      return if search.blank?

      url = search.webhook_url.to_s.strip.presence || delivery.url
      return if url.blank?

      payload = delivery.request_payload.deep_stringify_keys
      attempt = delivery.attempt_count + 1
      delivery.update!(attempt_count: attempt)
      Community::DispatchSavedSearchWebhookJob.perform_later(
        search.id,
        url,
        payload,
        delivery_id: delivery.id,
        attempt: attempt
      )
    end
  end
end

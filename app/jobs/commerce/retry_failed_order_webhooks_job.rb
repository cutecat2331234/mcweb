# frozen_string_literal: true

module Commerce
  class RetryFailedOrderWebhooksJob < ApplicationJob
    queue_as :maintenance

    STALE_PENDING_AFTER = 5.minutes
    MAX_ATTEMPTS = Commerce::DispatchOrderWebhookJob::MAX_ATTEMPTS

    def perform
      Commerce::OrderWebhookDelivery
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
      payload = delivery.request_payload.deep_stringify_keys
      attempt = delivery.attempt_count + 1
      delivery.update!(attempt_count: attempt)
      secret = SiteSetting.get("store.order_webhook_secret", "").to_s.strip.presence
      Commerce::DispatchOrderWebhookJob.perform_later(
        delivery.url,
        payload,
        secret,
        delivery_id: delivery.id,
        attempt: attempt
      )
    end
  end
end

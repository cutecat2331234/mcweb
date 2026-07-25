# frozen_string_literal: true

module Community
  class RetryFailedForumEventWebhooksJob < ApplicationJob
    queue_as :maintenance

    STALE_PENDING_AFTER = 5.minutes
    MAX_ATTEMPTS = Community::DispatchForumEventWebhookJob::MAX_ATTEMPTS

    def perform
      Community::EventWebhookDelivery
        .where(status: "pending")
        .where(created_at: ...STALE_PENDING_AFTER.ago)
        .find_each do |delivery|
          if delivery.attempt_count < MAX_ATTEMPTS && delivery.request_payload.present?
            requeue_delivery(delivery)
          else
            delivery.update!(
              status: "failed",
              response_body: I18n.t("mcweb.services.errors.webhook_delivery_timeout").truncate(4000)
            )
          end
        end
    end

  private

    def requeue_delivery(delivery)
      payload = Community::BuildForumEventWebhookPayload.sanitize(
        delivery.request_payload,
        event_type: delivery.event_type,
        topic_id: delivery.topic&.public_id,
        post_id: delivery.forum_post_id
      )
      exportable = payload.present? &&
        Community::ForumEventWebhookPolicy.exportable_payload?(
          payload: payload,
          delivery: delivery
        )
      unless exportable && UrlSafety.public_http_url?(delivery.url)
        delivery.update!(
          status: "failed",
          request_payload: payload,
          response_body: I18n.t("mcweb.services.errors.webhook_delivery_timeout").truncate(4000)
        )
        return
      end

      attempt = delivery.attempt_count + 1
      delivery.update!(attempt_count: attempt, request_payload: payload)
      Community::DispatchForumEventWebhookJob.perform_later(
        delivery.url,
        payload,
        delivery_id: delivery.id,
        attempt: attempt
      )
    end
  end
end

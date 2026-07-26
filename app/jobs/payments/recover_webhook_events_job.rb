# frozen_string_literal: true

module Payments
  class RecoverWebhookEventsJob < ApplicationJob
    queue_as :maintenance

    BATCH_SIZE = 100

    def perform
      recoverable_ids.each do |event_id|
        Payments::ProcessWebhookJob.perform_later(
          webhook_event_id: event_id,
          source: "automatic"
        )
      end
    end

    private

    def recoverable_ids
      received = Payments::WebhookEvent
        .where(status: :received)
        .where("updated_at < ?", Payments::ReceiveWebhook::RECEIVED_RECLAIM_AFTER.ago)
      due = Payments::WebhookEvent.retry_due
      stale = Payments::WebhookEvent.stale_processing

      Payments::WebhookEvent
        .where(id: received.select(:id))
        .or(Payments::WebhookEvent.where(id: due.select(:id)))
        .or(Payments::WebhookEvent.where(id: stale.select(:id)))
        .order(:updated_at)
        .limit(BATCH_SIZE)
        .pluck(:id)
    end
  end
end

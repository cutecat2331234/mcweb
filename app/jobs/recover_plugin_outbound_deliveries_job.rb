# frozen_string_literal: true

class RecoverPluginOutboundDeliveriesJob < ApplicationJob
  queue_as :maintenance

  PROCESSING_TIMEOUT = 15.minutes
  ENQUEUE_GRACE = 5.minutes

  def perform
    recover_stuck_processing
    requeue_lost_deliveries
  end

  private

  def recover_stuck_processing
    PluginOutboundDelivery
      .where(status: "processing", updated_at: ..PROCESSING_TIMEOUT.ago)
      .find_each do |delivery|
        delivery.with_lock do
          next unless delivery.status == "processing" &&
            delivery.updated_at <= PROCESSING_TIMEOUT.ago

          if delivery.attempts < delivery.max_attempts
            delivery.update!(
              status: "retrying",
              next_attempt_at: Time.current,
              last_error_code: "processing_timeout",
              response_summary: "delivery worker did not finish before the processing timeout"
            )
            enqueue_after_commit(delivery.public_id)
          else
            delivery.update!(
              status: "failed",
              next_attempt_at: nil,
              last_error_code: "processing_timeout",
              response_summary: "delivery worker exceeded the processing timeout",
              delivered_at: Time.current
            )
          end
        end
      end
  end

  def requeue_lost_deliveries
    PluginOutboundDelivery
      .where(status: "queued", created_at: ..ENQUEUE_GRACE.ago)
      .or(
        PluginOutboundDelivery.where(
          status: "retrying",
          next_attempt_at: ..ENQUEUE_GRACE.ago
        )
      )
      .find_each { |delivery| enqueue_after_commit(delivery.public_id) }
  end

  def enqueue_after_commit(public_id)
    ActiveRecord.after_all_transactions_commit do
      PluginOutboundDeliveryJob.perform_later(public_id)
    end
  end
end

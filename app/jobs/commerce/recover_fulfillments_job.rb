# frozen_string_literal: true

module Commerce
  class RecoverFulfillmentsJob < ApplicationJob
    queue_as :maintenance

    STALE_PROCESSING_AFTER = 30.minutes
    BATCH_SIZE = 100

    def perform(now = Time.current)
      recover_interrupted(now)
      enqueue_due_retries(now)
    end

    private

    def recover_interrupted(now)
      Commerce::Fulfillment
        .processing
        .where(updated_at: ..STALE_PROCESSING_AFTER.ago(now))
        .limit(BATCH_SIZE)
        .find_each do |fulfillment|
          fulfillment.with_lock do
            next unless fulfillment.processing?
            next if fulfillment.connector_tasks.where(status: %w[pending claimed]).exists?

            fulfillment.mark_failed!(
              error: "worker_interrupted",
              attempt: fulfillment.current_dispatch_attempt
            )
          end
        rescue ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError => error
          Rails.logger.warn(
            "[Commerce::RecoverFulfillmentsJob] interrupted recovery skipped " \
            "fulfillment_id=#{fulfillment.id} error=#{error.class}"
          )
        end
    end

    def enqueue_due_retries(now)
      Commerce::Fulfillment
        .failed
        .where(next_attempt_at: ..now)
        .limit(BATCH_SIZE)
        .find_each do |fulfillment|
          should_enqueue = fulfillment.with_lock do
            next false unless fulfillment.failed?
            next false unless fulfillment.next_attempt_at&.<= now
            next false unless fulfillment.retryable?

            fulfillment.update!(
              status: "pending",
              next_attempt_at: nil,
              last_error: nil
            )
            true
          end
          Minecraft::EnsureInstanceRunningJob.perform_later(fulfillment.id) if should_enqueue
        rescue ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError => error
          Rails.logger.warn(
            "[Commerce::RecoverFulfillmentsJob] retry skipped " \
            "fulfillment_id=#{fulfillment.id} error=#{error.class}"
          )
        end
    end
  end
end

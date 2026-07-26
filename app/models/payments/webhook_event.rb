module Payments
  class WebhookEvent < ApplicationRecord
    PROCESSING_TIMEOUT = 5.minutes

    belongs_to :last_replayed_by, class_name: "User", optional: true
    has_one :late_payment_case,
      class_name: "Payments::LatePaymentCase",
      foreign_key: :payment_webhook_event_id,
      dependent: :restrict_with_error

    enum :status, {
      received: "received",
      processing: "processing",
      processed: "processed",
      failed: "failed",
      dead_letter: "dead_letter"
    }, validate: true

    validates :provider, presence: true
    validates :event_id, presence: true, uniqueness: { scope: :provider }
    validates :event_type, presence: true
    validates :attempt_count, :retry_count, :manual_replay_count,
      numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    scope :unprocessed, -> { where(status: %i[received processing]) }
    scope :retry_due, lambda {
      where(status: :failed)
        .where("next_retry_at IS NULL OR next_retry_at <= ?", Time.current)
    }
    scope :stale_processing, lambda {
      where(status: :processing)
        .where(
          "COALESCE(processing_started_at, updated_at) < ?",
          PROCESSING_TIMEOUT.ago
        )
    }

    def mark_processed!
      update!(
        status: :processed,
        processed_at: Time.current,
        processing_started_at: nil,
        processing_token: nil,
        next_retry_at: nil,
        dead_lettered_at: nil,
        error_message: nil,
        last_error_code: nil
      )
    end

    def processing_stale?
      return false unless processing?

      (processing_started_at || updated_at) < PROCESSING_TIMEOUT.ago
    end

    def verified_payload?
      verified_at.present? &&
        payload_digest.present? &&
        ActiveSupport::SecurityUtils.secure_compare(
          payload_digest,
          Payments::WebhookPayload.digest(payload, event_type: event_type)
        )
    end

    def manually_replayable?
      (dead_letter? || failed? || processing_stale?) &&
        verified_payload? &&
        Payments::WebhookPayload.replayable?(provider: provider, event_type: event_type)
    end
  end
end

module Payments
  class WebhookEvent < ApplicationRecord
    enum :status, { received: "received", processing: "processing", processed: "processed", failed: "failed" }, validate: true

    validates :provider, presence: true
    validates :event_id, presence: true, uniqueness: { scope: :provider }
    validates :event_type, presence: true

    scope :unprocessed, -> { where(status: %i[received processing]) }

    def mark_processed!
      update!(status: :processed, processed_at: Time.current)
    end

    def mark_failed!(message)
      update!(status: :failed, error_message: message, processed_at: Time.current)
    end
  end
end

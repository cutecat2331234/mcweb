# frozen_string_literal: true

module Commerce
  class DisputeEvent < ApplicationRecord
    self.table_name = "store_dispute_events"

    SOURCES = %w[channel manual policy system].freeze

    belongs_to :dispute,
               class_name: "Commerce::Dispute",
               foreign_key: :store_dispute_id
    belongs_to :payment_webhook_event,
               class_name: "Payments::WebhookEvent",
               optional: true
    belongs_to :actor, class_name: "User", optional: true

    validates :idempotency_key, :source, :event_type, presence: true
    validates :idempotency_key, uniqueness: true
    validates :source, inclusion: { in: SOURCES }
    validates :payload_digest,
              format: { with: /\A[0-9a-f]{64}\z/ },
              allow_nil: true

    scope :timeline, -> { order(created_at: :asc, id: :asc) }

    def readonly?
      persisted?
    end
  end
end

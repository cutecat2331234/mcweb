module Commerce
  class FulfillmentAttempt < ApplicationRecord
    belongs_to :fulfillment, class_name: "Commerce::Fulfillment", foreign_key: :store_fulfillment_id
    belongs_to :actor, class_name: "User", optional: true

    validates :status, presence: true
    validates :attempt_number, numericality: { only_integer: true, greater_than: 0 },
                               uniqueness: { scope: :store_fulfillment_id }
    validates :idempotency_key, presence: true, uniqueness: true
    validates :trigger, inclusion: { in: %w[automatic manual recovery] }
    validates :action, inclusion: { in: %w[dispatch retry cancel] }

    scope :recent, -> { order(created_at: :desc) }
    scope :dispatches, -> { where(action: "dispatch") }
    scope :unfinished, -> { where(status: %w[pending processing]) }
  end
end

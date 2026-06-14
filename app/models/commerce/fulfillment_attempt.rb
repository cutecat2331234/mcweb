module Commerce
  class FulfillmentAttempt < ApplicationRecord
    belongs_to :fulfillment, class_name: "Commerce::Fulfillment", foreign_key: :store_fulfillment_id

    validates :status, presence: true

    scope :recent, -> { order(created_at: :desc) }
  end
end

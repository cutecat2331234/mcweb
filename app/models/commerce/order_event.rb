module Commerce
  class OrderEvent < ApplicationRecord
    belongs_to :order, class_name: "Commerce::Order", foreign_key: :store_order_id
    belongs_to :actor, class_name: "User", optional: true

    validates :event_type, presence: true

    scope :chronological, -> { order(:created_at) }
  end
end

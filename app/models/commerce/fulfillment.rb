module Commerce
  class Fulfillment < ApplicationRecord
    belongs_to :order, class_name: "Commerce::Order", foreign_key: :store_order_id
    belongs_to :order_item, class_name: "Commerce::OrderItem", foreign_key: :store_order_item_id
    has_many :attempts, class_name: "Commerce::FulfillmentAttempt", foreign_key: :store_fulfillment_id, dependent: :destroy
    has_many :connector_tasks, class_name: "Minecraft::ConnectorTask", foreign_key: :store_fulfillment_id, dependent: :nullify

    enum :status, { pending: "pending", processing: "processing", fulfilled: "fulfilled", failed: "failed" }, validate: true

    validates :delivery_id, presence: true, uniqueness: true

    before_validation :generate_delivery_id, on: :create

    def mark_fulfilled!
      update!(status: :fulfilled, fulfilled_at: Time.current)
    end

    def mark_failed!(error:)
      increment!(:attempts_count)
      update!(status: :failed, last_error: error)
    end

    private

    def generate_delivery_id
      self.delivery_id ||= SecureRandom.uuid
    end
  end
end

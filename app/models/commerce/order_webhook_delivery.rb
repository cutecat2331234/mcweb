# frozen_string_literal: true

module Commerce
  class OrderWebhookDelivery < ApplicationRecord
    self.table_name = "store_order_webhook_deliveries"

    STATUSES = %w[pending success failed].freeze

    validates :event_type, :url, :status, presence: true
    validates :status, inclusion: { in: STATUSES }
  end
end

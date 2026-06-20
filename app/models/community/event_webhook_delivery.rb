# frozen_string_literal: true

module Community
  class EventWebhookDelivery < ApplicationRecord
    self.table_name = "forum_event_webhook_deliveries"

    belongs_to :topic, class_name: "Community::Topic", foreign_key: :forum_topic_id, optional: true
    belongs_to :post, class_name: "Community::Post", foreign_key: :forum_post_id, optional: true

    scope :recent, -> { order(created_at: :desc) }
  end
end

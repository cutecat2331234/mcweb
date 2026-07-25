# frozen_string_literal: true

module Community
  class EventWebhookDelivery < ApplicationRecord
    self.table_name = "forum_event_webhook_deliveries"

    belongs_to :topic, class_name: "Community::Topic", foreign_key: :forum_topic_id, optional: true
    belongs_to :post, class_name: "Community::Post", foreign_key: :forum_post_id, optional: true

    before_validation :sanitize_request_payload

    validates :event_type, inclusion: { in: Community::BuildForumEventWebhookPayload::EVENT_TYPES }
    validates :url, presence: true

    scope :recent, -> { order(created_at: :desc) }

    private

    def sanitize_request_payload
      return if request_payload.blank?

      self.request_payload = Community::BuildForumEventWebhookPayload.sanitize(
        request_payload,
        event_type: event_type,
        topic_id: topic&.public_id,
        post_id: forum_post_id,
        occurred_at: request_payload.to_h.with_indifferent_access[:occurred_at]
      )
    end
  end
end

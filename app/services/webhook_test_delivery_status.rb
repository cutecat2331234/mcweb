# frozen_string_literal: true

class WebhookTestDeliveryStatus
  def self.forum_last
    serialize(
      Community::SavedSearchWebhookDelivery
        .where("request_payload @> ?", { test: true }.to_json)
        .order(created_at: :desc)
        .first
    )
  end

  def self.forum_event_last
    serialize(
      Community::EventWebhookDelivery
        .where("request_payload @> ?", { test: true }.to_json)
        .order(created_at: :desc)
        .first
    )
  end

  def self.store_last
    serialize(
      Commerce::OrderWebhookDelivery
        .where("order_public_id LIKE ?", "test_%")
        .order(created_at: :desc)
        .first
    )
  end

  def self.serialize(delivery)
    return nil unless delivery

    {
      event_type: delivery.event_type,
      status: delivery.status,
      response_code: delivery.response_code,
      created_at: I18n.l(delivery.created_at, format: :short)
    }
  end

  private_class_method :serialize
end

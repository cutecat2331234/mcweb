# frozen_string_literal: true

module Commerce
  class DispatchTestOrderWebhook < ApplicationService
    EVENT_TYPES = %w[
      order.test order.created order.paid order.status_changed
      order.shipped order.refunded order.cancelled order.fulfilled
    ].freeze

    def initialize(event_type: "order.test")
      @event_type = event_type.to_s
    end

    def call
      return ServiceResult.failure(error: "webhook_event_unsupported") unless EVENT_TYPES.include?(@event_type)

      url = SiteSetting.get("store.order_webhook_url", "").to_s.strip
      return ServiceResult.failure(error: "webhook_url_missing") if url.blank?
      return ServiceResult.failure(error: "webhook_url_private") unless UrlSafety.public_http_url?(url)

      payload = build_payload
      secret = SiteSetting.get("store.order_webhook_secret", "").to_s.strip.presence
      Commerce::DispatchOrderWebhookJob.perform_later(url, payload, secret)
      ServiceResult.success(queued: true, event_type: @event_type)
    end

  private

    def build_payload
      base = {
        event: @event_type,
        order_id: "test_#{SecureRandom.hex(6)}",
        order_number: "TEST-#{Time.current.to_i}",
        subtotal_cents: 1000,
        total_cents: 1000,
        currency: "CNY",
        user_id: nil,
        occurred_at: Time.current.iso8601,
        items: [
          {
            product_name: I18n.t("mcweb.commerce.webhook_test.product_name"),
            variant_name: I18n.t("mcweb.commerce.webhook_test.variant_name"),
            quantity: 1,
            unit_price_cents: 1000,
            total_cents: 1000
          }
        ],
        test: true
      }

      case @event_type
      when "order.created"
        base.merge(from_status: nil, to_status: "pending")
      when "order.paid"
        base.merge(from_status: "pending", to_status: "paid")
      when "order.status_changed"
        base.merge(from_status: "paid", to_status: "processing")
      when "order.shipped"
        base.merge(from_status: "processing", to_status: "shipped", tracking_number: "TEST-TRACK-001")
      when "order.refunded"
        base.merge(from_status: "paid", to_status: "refunded", refund_amount_cents: 1000, refund_id: "test_refund_#{SecureRandom.hex(4)}")
      when "order.cancelled"
        base.merge(from_status: "pending", to_status: "cancelled", cancel_reason: I18n.t("mcweb.commerce.webhook_test.cancel_reason"))
      when "order.fulfilled"
        base.merge(from_status: "processing", to_status: "fulfilled")
      else
        base.merge(from_status: nil, to_status: "test")
      end
    end
  end
end

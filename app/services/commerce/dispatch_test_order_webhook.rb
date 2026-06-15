# frozen_string_literal: true

module Commerce
  class DispatchTestOrderWebhook < ApplicationService
    EVENT_TYPES = %w[order.test order.created order.paid order.status_changed order.shipped].freeze

    def initialize(event_type: "order.test")
      @event_type = event_type.to_s
    end

    def call
      return ServiceResult.failure(error: "不支持的事件类型") unless EVENT_TYPES.include?(@event_type)

      url = SiteSetting.get("store.order_webhook_url", "").to_s.strip
      return ServiceResult.failure(error: "未配置 Webhook URL") if url.blank?

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
            product_name: "Webhook 测试商品",
            variant_name: "默认",
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
      else
        base.merge(from_status: nil, to_status: "test")
      end
    end
  end
end

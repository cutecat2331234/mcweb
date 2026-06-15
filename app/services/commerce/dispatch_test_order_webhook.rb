# frozen_string_literal: true

module Commerce
  class DispatchTestOrderWebhook < ApplicationService
    def call
      url = SiteSetting.get("store.order_webhook_url", "").to_s.strip
      return ServiceResult.failure(error: "未配置 Webhook URL") if url.blank?

      payload = {
        event: "order.test",
        order_id: "test_#{SecureRandom.hex(6)}",
        order_number: "TEST-#{Time.current.to_i}",
        from_status: nil,
        to_status: "test",
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

      secret = SiteSetting.get("store.order_webhook_secret", "").to_s.strip.presence
      Commerce::DispatchOrderWebhookJob.perform_later(url, payload, secret)
      ServiceResult.success(queued: true)
    end
  end
end

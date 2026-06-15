# frozen_string_literal: true

module Commerce
  class DispatchOrderWebhook < ApplicationService
    def initialize(order:, event_type:, from_status: nil, to_status: nil, extra: {})
      @order = order
      @event_type = event_type.to_s
      @from_status = from_status
      @to_status = to_status
      @extra = extra || {}
    end

    def call
      url = SiteSetting.get("store.order_webhook_url", "").to_s.strip
      return ServiceResult.success(skipped: true) if url.blank?

      payload = {
        event: @event_type,
        order_id: @order.public_id,
        order_number: @order.order_number,
        from_status: @from_status,
        to_status: @to_status || @order.status,
        total_cents: @order.total_cents,
        currency: @order.currency,
        user_id: @order.user_id,
        occurred_at: Time.current.iso8601
      }.merge(@extra.symbolize_keys)

      secret = SiteSetting.get("store.order_webhook_secret", "").to_s.strip.presence
      Commerce::DispatchOrderWebhookJob.perform_later(url, payload, secret)
      ServiceResult.success(queued: true)
    end
  end
end

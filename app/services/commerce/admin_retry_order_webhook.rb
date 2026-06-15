# frozen_string_literal: true

module Commerce
  class AdminRetryOrderWebhook < ApplicationService
    def initialize(delivery:)
      @delivery = delivery
    end

    def call
      return ServiceResult.failure(error: "仅失败记录可重试") unless @delivery.status == "failed"
      return ServiceResult.failure(error: "缺少请求内容，无法重试") if @delivery.request_payload.blank?

      url = @delivery.url.presence || SiteSetting.get("store.order_webhook_url", "").to_s.strip
      return ServiceResult.failure(error: "未配置 Webhook URL") if url.blank?

      payload = @delivery.request_payload.deep_stringify_keys
      secret = SiteSetting.get("store.order_webhook_secret", "").to_s.strip.presence
      Commerce::DispatchOrderWebhookJob.perform_later(url, payload, secret)
      ServiceResult.success(queued: true)
    end
  end
end

# frozen_string_literal: true

module Community
  class AdminRetrySavedSearchWebhook < ApplicationService
    def initialize(delivery:)
      @delivery = delivery
    end

    def call
      return ServiceResult.failure(error: "仅失败记录可重试") unless @delivery.status == "failed"
      return ServiceResult.failure(error: "缺少请求内容，无法重试") if @delivery.request_payload.blank?

      search = @delivery.saved_search
      return ServiceResult.failure(error: "关联搜索不存在") if search.blank?

      url = search.webhook_url.to_s.strip.presence || @delivery.url
      return ServiceResult.failure(error: "未配置 Webhook URL") if url.blank?

      payload = @delivery.request_payload.deep_stringify_keys
      secret = SiteSetting.get("forum.saved_search_webhook_secret", "").to_s.strip.presence
      Community::DispatchSavedSearchWebhookJob.perform_later(search.id, url, payload, secret: secret)
      ServiceResult.success(queued: true)
    end
  end
end

# frozen_string_literal: true

module Administration
  class SystemMailer < ApplicationMailer
    def webhook_failure_alert(to:, forum_failed:, store_failed:, forum_threshold:, store_threshold:, forum_alert:, store_alert:, stats:)
      @forum_failed = forum_failed
      @store_failed = store_failed
      @forum_threshold = forum_threshold
      @store_threshold = store_threshold
      @forum_alert = forum_alert
      @store_alert = store_alert
      @stats = stats
      @forum_url = admin_forum_webhook_deliveries_url(status: "failed", created_from: 24.hours.ago.to_date.to_s)
      @store_url = admin_store_webhook_deliveries_url(status: "failed", created_from: 24.hours.ago.to_date.to_s)

      mail(to: to, subject: "[McWeb] Webhook 投递失败告警（24 小时）")
    end
  end
end

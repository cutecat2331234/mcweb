# frozen_string_literal: true

module Administration
  class SystemMailer < ApplicationMailer
    def webhook_failure_alert(to:, forum_failed:, store_failed:, forum_threshold:, store_threshold:, forum_alert:, store_alert:, stats:, locale: nil)
      @recipient_locale = Mcweb::LocaleResolver.resolve(locale)
      @forum_failed = forum_failed
      @store_failed = store_failed
      @forum_threshold = forum_threshold
      @store_threshold = store_threshold
      @forum_alert = forum_alert
      @store_alert = store_alert
      @stats = stats
      @forum_url = admin_forum_webhook_deliveries_url(status: "failed", created_from: 24.hours.ago.to_date.to_s)
      @store_url = admin_store_webhook_deliveries_url(status: "failed", created_from: 24.hours.ago.to_date.to_s)

      mail(to: to, subject: recipient_t("mcweb.mail.commerce.webhook_failure.subject"))
    end
  end
end

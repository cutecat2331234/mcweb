# frozen_string_literal: true

class WebhookFailureAlertCheck < ApplicationService
  COOLDOWN_KEY = "webhook.failure_alert_last_sent_at"
  THRESHOLD_KEY = "webhook.failure_alert_threshold"
  EMAIL_KEY = "webhook.failure_alert_email"
  COOLDOWN_HOURS_KEY = "webhook.failure_alert_cooldown_hours"

  def call
    threshold = SiteSetting.get(THRESHOLD_KEY, "5").to_i
    return ServiceResult.success(skipped: :disabled) if threshold <= 0

    email = SiteSetting.get(EMAIL_KEY, "").to_s.strip
    return ServiceResult.success(skipped: :no_email) if email.blank?

    return ServiceResult.success(skipped: :cooldown) if within_cooldown?

    stats = WebhookDeliveryStats.summary
    forum_failed = stats.dig(:forum, :failed).to_i
    store_failed = stats.dig(:store, :failed).to_i
    return ServiceResult.success(skipped: :below_threshold) if forum_failed < threshold && store_failed < threshold

    Administration::SystemMailer.webhook_failure_alert(
      to: email,
      forum_failed: forum_failed,
      store_failed: store_failed,
      threshold: threshold,
      stats: stats
    ).deliver_now

    SiteSetting.set(COOLDOWN_KEY, Time.current.iso8601)
    ServiceResult.success(sent: true, forum_failed: forum_failed, store_failed: store_failed)
  end

private

  def within_cooldown?
    last_sent = SiteSetting.get(COOLDOWN_KEY, "").to_s
    return false if last_sent.blank?

    parsed = Time.zone.parse(last_sent) rescue nil
    return false unless parsed

    hours = SiteSetting.get(COOLDOWN_HOURS_KEY, "6").to_i
    hours = 6 if hours <= 0
    parsed > hours.hours.ago
  end
end

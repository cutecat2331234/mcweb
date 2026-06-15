# frozen_string_literal: true

class WebhookFailureAlertCheck < ApplicationService
  COOLDOWN_KEY = "webhook.failure_alert_last_sent_at"
  FORUM_THRESHOLD_KEY = "webhook.failure_alert_forum_threshold"
  STORE_THRESHOLD_KEY = "webhook.failure_alert_store_threshold"
  LEGACY_THRESHOLD_KEY = "webhook.failure_alert_threshold"
  EMAIL_KEY = "webhook.failure_alert_email"
  COOLDOWN_HOURS_KEY = "webhook.failure_alert_cooldown_hours"

  def call
    forum_threshold = threshold_for(FORUM_THRESHOLD_KEY)
    store_threshold = threshold_for(STORE_THRESHOLD_KEY)
    return ServiceResult.success(skipped: :disabled) if forum_threshold <= 0 && store_threshold <= 0

    email = SiteSetting.get(EMAIL_KEY, "").to_s.strip
    return ServiceResult.success(skipped: :no_email) if email.blank?

    return ServiceResult.success(skipped: :cooldown) if within_cooldown?

    stats = WebhookDeliveryStats.summary
    forum_failed = stats.dig(:forum, :failed).to_i
    store_failed = stats.dig(:store, :failed).to_i
    forum_alert = forum_threshold.positive? && forum_failed >= forum_threshold
    store_alert = store_threshold.positive? && store_failed >= store_threshold
    return ServiceResult.success(skipped: :below_threshold) unless forum_alert || store_alert

    Administration::SystemMailer.webhook_failure_alert(
      to: email,
      forum_failed: forum_failed,
      store_failed: store_failed,
      forum_threshold: forum_threshold,
      store_threshold: store_threshold,
      forum_alert: forum_alert,
      store_alert: store_alert,
      stats: stats
    ).deliver_now

    SiteSetting.set(COOLDOWN_KEY, Time.current.iso8601)
    ServiceResult.success(
      sent: true,
      forum_failed: forum_failed,
      store_failed: store_failed,
      forum_alert: forum_alert,
      store_alert: store_alert
    )
  end

private

  def threshold_for(key)
    value = SiteSetting.get(key, "").to_s
    return SiteSetting.get(LEGACY_THRESHOLD_KEY, "5").to_i if value.blank?

    value.to_i
  end

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

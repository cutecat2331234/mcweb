# frozen_string_literal: true

require "json"
require "uri"
require "url_safety"

class PluginOutboundDeliveryJob < ApplicationJob
  queue_as :plugins

  RETRY_DELAYS = [ 30.seconds, 2.minutes, 10.minutes, 1.hour, 6.hours ].freeze
  RESPONSE_LIMIT = 1_000

  class DeliveryFailure < StandardError
    attr_reader :code, :http_status

    def initialize(code, message, http_status: nil)
      @code = code.to_s
      @http_status = http_status
      super(message)
    end
  end

  def perform(public_id)
    delivery = claim(public_id)
    return unless delivery

    outcome = dispatch(delivery)
    finish(delivery, **outcome)
  rescue DeliveryFailure => e
    retry_or_fail(delivery, code: e.code, message: e.message, http_status: e.http_status) if delivery
  rescue StandardError => e
    retry_or_fail(delivery, code: "delivery_error", message: e.class.name) if delivery
  end

  private

  def claim(public_id)
    PluginOutboundDelivery.transaction do
      delivery = PluginOutboundDelivery.lock.find_by(public_id:)
      return unless delivery
      return if delivery.terminal? || delivery.status == "processing"
      return if delivery.next_attempt_at && delivery.next_attempt_at > Time.current

      delivery.update!(
        status: "processing",
        attempts: delivery.attempts + 1,
        next_attempt_at: nil,
        last_error_code: nil,
        response_summary: nil
      )
      delivery
    end
  end

  def dispatch(delivery)
    case delivery.kind
    when "notification" then deliver_notification(delivery)
    when "mail" then deliver_mail(delivery)
    when "webhook" then deliver_webhook(delivery)
    else raise DeliveryFailure.new("unsupported_kind", "unsupported delivery kind")
    end
  end

  def deliver_notification(delivery)
    user = delivery.user
    type = delivery.payload.fetch("notification_type")
    unless user&.session_eligible? &&
        NotificationPreference.enabled?(user, channel: "in_app", notification_type: type)
      return { status: "suppressed", response_summary: "recipient preference or account policy" }
    end

    notification = Notification.notify!(
      user:,
      notification_type: type,
      title: delivery.payload.fetch("title"),
      body: delivery.payload["body"],
      metadata: delivery.payload.fetch("metadata", {})
    )
    {
      status: "succeeded",
      response_summary: "notification:#{notification.id}"
    }
  end

  def deliver_mail(delivery)
    user = delivery.user
    type = delivery.payload.fetch("notification_type")
    unless user&.session_eligible? &&
        Community::InstantEmailDelivery.allowed?(user, notification_type: type)
      return { status: "suppressed", response_summary: "recipient preference or account policy" }
    end

    PluginDeliveryMailer.delivery(delivery.id).deliver_now
    { status: "succeeded", response_summary: "accepted by mail transport" }
  end

  def deliver_webhook(delivery)
    uri = URI.parse(delivery.destination)
    raise DeliveryFailure.new("unsafe_url", "webhook destination is not public") unless
      UrlSafety.public_http_url?(uri.to_s)

    body = JSON.generate(
      delivery.payload.merge("occurred_at" => delivery.created_at.iso8601(6))
    )
    headers = {
      "Content-Type" => "application/json",
      "User-Agent" => "McWeb-Plugin-Delivery/1",
      "X-McWeb-Plugin" => delivery.owner_plugin_id,
      "X-McWeb-Delivery" => delivery.public_id
    }
    signature = WebhookSignature.header_for(delivery.secret, body)
    headers["X-McWeb-Signature"] = signature if signature
    response = UrlSafety.safe_http_post(
      uri,
      body:,
      open_timeout: 5,
      read_timeout: 10,
      headers:
    )
    unless response
      raise DeliveryFailure.new("network_failure", "webhook request did not return a response")
    end
    status = response.code.to_i
    unless status.between?(200, 299)
      raise DeliveryFailure.new(
        "http_error",
        "webhook returned HTTP #{status}",
        http_status: status
      )
    end
    {
      status: "succeeded",
      http_status: status,
      response_summary: response.body.to_s.encode(
        Encoding::UTF_8,
        invalid: :replace,
        undef: :replace,
        replace: "?"
      ).slice(0, RESPONSE_LIMIT)
    }
  rescue URI::InvalidURIError
    raise DeliveryFailure.new("unsafe_url", "webhook destination is invalid")
  end

  def finish(delivery, status:, response_summary:, http_status: nil)
    delivery.with_lock do
      delivery.update!(
        status:,
        last_http_status: http_status,
        response_summary: response_summary.to_s.slice(0, RESPONSE_LIMIT),
        delivered_at: Time.current,
        next_attempt_at: nil
      )
    end
  end

  def retry_or_fail(delivery, code:, message:, http_status: nil)
    should_retry = false
    delivery.with_lock do
      should_retry = delivery.attempts < delivery.max_attempts
      delay = RETRY_DELAYS.fetch(
        [ delivery.attempts - 1, RETRY_DELAYS.length - 1 ].min
      )
      delivery.update!(
        status: should_retry ? "retrying" : "failed",
        next_attempt_at: should_retry ? Time.current + delay : nil,
        last_http_status: http_status,
        last_error_code: code,
        response_summary: message.to_s.slice(0, RESPONSE_LIMIT),
        delivered_at: should_retry ? nil : Time.current
      )
    end
    self.class.set(wait_until: delivery.next_attempt_at).perform_later(delivery.public_id) if should_retry
  end
end

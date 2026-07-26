# frozen_string_literal: true

module Commerce
  class WebhooksController < ApplicationController
    MAX_WEBHOOK_BODY_BYTES = 256.kilobytes

    skip_before_action :verify_authenticity_token

    def create
      provider = params[:provider].to_s
      return head :not_found unless Payments::Provider.known?(provider)
      return head :content_too_large if request.content_length.to_i > MAX_WEBHOOK_BODY_BYTES

      rate_result = Administration::RateLimiter.call(
        key: "payment_webhook:#{provider}:#{request.remote_ip}",
        limit: 120,
        window: 1.minute
      )
      return head :too_many_requests if rate_result.failure?

      payload_body = webhook_payload_body
      return head :content_too_large if payload_body.bytesize > MAX_WEBHOOK_BODY_BYTES

      signature = request.headers["Stripe-Signature"].presence || request.headers["X-Webhook-Signature"].to_s
      identifiers = webhook_identifiers(provider, payload_body)
      return head :bad_request unless identifiers

      result = Payments::ReceiveWebhook.call(
        provider: provider,
        event_id: identifiers.fetch(:event_id),
        event_type: identifiers.fetch(:event_type),
        payload: payload_body,
        signature: signature,
        headers: serializable_webhook_headers
      )
      if result.code == Payments::ReceiveWebhook::STRIPE_IDENTITY_UNAVAILABLE_CODE
        response.set_header("Retry-After", result.retry_after.to_s)
        return head :service_unavailable
      end
      return head :bad_request if result.failure?

      if result.value[:should_process]
        Payments::ProcessWebhookJob.perform_later(
          webhook_event_id: result.value.fetch(:event).id
        )
      end

      head :ok
    end

    private

    def webhook_payload_body
      request.raw_post.presence || request.request_parameters.to_json
    end

    def webhook_identifiers(provider, payload_body)
      if provider == "stripe"
        signed_body = JSON.parse(payload_body)
        event_id = signed_body["id"].to_s
        event_type = signed_body["type"].to_s
      else
        event_id = params[:event_id].presence ||
          request.headers["X-Webhook-Id"].presence ||
          body_value(payload_body, "id") ||
          payload_fingerprint(payload_body)
        event_type = params[:event_type].presence ||
          request.headers["X-Webhook-Event"].presence ||
          body_value(payload_body, "type") ||
          "unknown"
      end

      return if event_id.blank? || event_type.blank?

      { event_id: event_id, event_type: event_type }
    rescue JSON::ParserError
      nil
    end

    def body_value(payload_body, key)
      JSON.parse(payload_body)[key].presence
    rescue JSON::ParserError
      nil
    end

    def payload_fingerprint(payload_body)
      "sha256:#{Digest::SHA256.hexdigest(payload_body)}"
    end

    def serializable_webhook_headers
      request.headers.env.slice(
        "HTTP_STRIPE_SIGNATURE",
        "HTTP_X_WEBHOOK_SIGNATURE",
        "HTTP_X_WEBHOOK_ID",
        "HTTP_X_WEBHOOK_EVENT"
      ).transform_values(&:to_s)
    end
  end
end

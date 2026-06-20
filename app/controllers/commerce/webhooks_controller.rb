# frozen_string_literal: true

module Commerce
  class WebhooksController < ApplicationController
    skip_before_action :verify_authenticity_token

    def create
      provider = params[:provider].to_s
      return head :not_found unless Payments::Provider.known?(provider)

      rate_result = Administration::RateLimiter.call(
        key: "payment_webhook:#{provider}:#{request.remote_ip}",
        limit: 120,
        window: 1.minute
      )
      return head :too_many_requests if rate_result.failure?

      adapter = Payments::Provider.for(provider)
      payload_body = webhook_payload_body
      signature = request.headers["Stripe-Signature"].presence || request.headers["X-Webhook-Signature"].to_s

      unless adapter.verify_webhook_signature(
        payload: payload_body,
        signature: signature,
        headers: serializable_webhook_headers
      )
        return head :bad_request
      end

      Payments::ProcessWebhookJob.perform_later(
        provider: provider,
        event_id: webhook_event_id,
        event_type: webhook_event_type,
        payload: webhook_payload,
        signature: signature,
        headers: serializable_webhook_headers
      )

      head :ok
    end

    private

    def webhook_payload_body
      request.raw_post.presence || request.request_parameters.to_json
    end

    def webhook_payload
      request.raw_post.presence || request.request_parameters
    end

    def webhook_event_id
      params[:event_id].presence ||
        request.headers["X-Webhook-Id"].presence ||
        body_event_id ||
        payload_fingerprint
    end

    def body_event_id
      body = request.raw_post
      return if body.blank?

      JSON.parse(body)["id"].presence
    rescue JSON::ParserError
      nil
    end

    def payload_fingerprint
      body = request.raw_post
      digest_source =
        if body.present?
          body
        else
          request.request_parameters.to_json
        end

      "sha256:#{Digest::SHA256.hexdigest(digest_source)}"
    end

    def webhook_event_type
      params[:event_type].presence ||
        request.headers["X-Webhook-Event"].presence ||
        body_event_type ||
        "unknown"
    end

    def body_event_type
      body = request.raw_post
      return if body.blank?

      JSON.parse(body)["type"].presence
    rescue JSON::ParserError
      nil
    end

    def serializable_webhook_headers
      request.headers.env.select { |key, _| key.start_with?("HTTP_") }.transform_values(&:to_s)
    end
  end
end

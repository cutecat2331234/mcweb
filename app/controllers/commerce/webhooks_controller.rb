# frozen_string_literal: true

module Commerce
  class WebhooksController < ApplicationController
    skip_before_action :verify_authenticity_token

    def create
      result = Payments::WebhookProcessor.call(
        provider: params[:provider],
        event_id: webhook_event_id,
        event_type: webhook_event_type,
        payload: request.raw_post.presence || request.request_parameters,
        signature: request.headers["Stripe-Signature"].presence || request.headers["X-Webhook-Signature"].to_s,
        headers: request.headers.env.select { |k, _| k.start_with?("HTTP_") }
      )

      if result.success?
        head :ok
      else
        head :unprocessable_entity
      end
    end

    private

    def webhook_event_id
      params[:event_id].presence ||
        request.headers["X-Webhook-Id"].presence ||
        body_event_id ||
        SecureRandom.uuid
    end

    def body_event_id
      body = request.raw_post
      return if body.blank?

      JSON.parse(body)["id"].presence
    rescue JSON::ParserError
      nil
    end

    def webhook_event_type
      params[:event_type].presence || request.headers["X-Webhook-Event"].presence || "unknown"
    end
  end
end

# frozen_string_literal: true

module Commerce
  class DispatchOrderWebhookJob < ApplicationJob
    queue_as :default

    def perform(url, payload, secret = nil)
      delivery = Commerce::OrderWebhookDelivery.create!(
        event_type: payload["event"].to_s,
        order_public_id: payload["order_id"].to_s.presence,
        url: url,
        status: "pending"
      )

      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 10

      body = payload.to_json
      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request.body = body
      if secret.present?
        signature = OpenSSL::HMAC.hexdigest("SHA256", secret, body)
        request["X-McWeb-Signature"] = "sha256=#{signature}"
      end

      response = http.request(request)
      delivery.update!(
        response_code: response.code.to_i,
        response_body: response.body.to_s.truncate(4000),
        status: response.code.to_i.between?(200, 299) ? "success" : "failed"
      )
    rescue StandardError => e
      delivery&.update!(status: "failed", response_body: "#{e.class}: #{e.message}".truncate(4000))
      Rails.logger.warn("[DispatchOrderWebhookJob] #{e.class}: #{e.message}")
    end
  end
end

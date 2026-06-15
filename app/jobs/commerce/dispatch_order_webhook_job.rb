# frozen_string_literal: true

module Commerce
  class DispatchOrderWebhookJob < ApplicationJob
    queue_as :default

    def perform(url, payload, secret = nil)
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
      http.request(request)
    rescue StandardError => e
      Rails.logger.warn("[DispatchOrderWebhookJob] #{e.class}: #{e.message}")
    end
  end
end

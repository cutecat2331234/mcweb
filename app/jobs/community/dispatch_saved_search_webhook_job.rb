# frozen_string_literal: true

module Community
  class DispatchSavedSearchWebhookJob < ApplicationJob
    queue_as :default

    def perform(url, payload)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request.body = payload.to_json
      http.request(request)
    rescue StandardError => e
      Rails.logger.warn("[DispatchSavedSearchWebhookJob] #{e.class}: #{e.message}")
    end
  end
end

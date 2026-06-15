# frozen_string_literal: true

module Community
  class DispatchSavedSearchWebhookJob < ApplicationJob
    queue_as :default

    def perform(saved_search_id, url, payload)
      delivery = Community::SavedSearchWebhookDelivery.create!(
        saved_search_id: saved_search_id,
        event_type: payload["event"].to_s,
        url: url,
        status: "pending",
        request_payload: payload
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
      response = http.request(request)
      delivery.update!(
        response_code: response.code.to_i,
        response_body: response.body.to_s.truncate(4000),
        status: response.code.to_i.between?(200, 299) ? "success" : "failed"
      )
    rescue StandardError => e
      delivery&.update!(status: "failed", response_body: "#{e.class}: #{e.message}".truncate(4000))
      Rails.logger.warn("[DispatchSavedSearchWebhookJob] #{e.class}: #{e.message}")
    end
  end
end

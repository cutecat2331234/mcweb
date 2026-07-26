# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "uri"

module Mcweb
  module DeveloperModeCapture
    Response = Data.define(:code, :body)
    Capture = Data.define(:capture_id, :path)
    FILTERED = "[FILTERED]"
    SENSITIVE_HEADER = /authorization|cookie|token|api[-_]?key|secret|signature/i
    WEB_PUSH_SENSITIVE_FIELDS = %i[
      auth
      endpoint
      p256dh
      private_key
      public_key
      vapid
    ].freeze

    class << self
      def capture_webhook!(uri:, body:, headers:, root: Rails.root, now: Time.current)
        capture_id = SecureRandom.uuid
        entry = {
          id: capture_id,
          captured_at: now.iso8601(6),
          method: "POST",
          url: filtered_url(uri),
          headers: filtered_headers(headers),
          payload: filtered_payload(body)
        }

        append_entry!(
          directory: root.join("tmp/developer-mode/webhooks"),
          now: now,
          entry: entry
        )

        Response.new(
          code: "202",
          body: JSON.generate(captured: true, capture_id: capture_id)
        )
      rescue StandardError => error
        Rails.logger.error(
          "[DeveloperModeCapture] webhook capture failed: #{error.class}: #{error.message}"
        )
        nil
      end

      def capture_web_push!(
        notification_id:,
        notification_type:,
        user_id:,
        subscription_id:,
        endpoint:,
        payload:,
        root: Rails.root,
        now: Time.current
      )
        capture_id = SecureRandom.uuid
        entry = {
          id: capture_id,
          captured_at: now.iso8601(6),
          notification: {
            id: notification_id,
            type: notification_type,
            user_id: user_id
          },
          subscription: {
            id: subscription_id,
            endpoint_sha256: Digest::SHA256.hexdigest(endpoint.to_s)
          },
          payload: filtered_payload(
            payload,
            additional_filters: WEB_PUSH_SENSITIVE_FIELDS
          )
        }
        path = append_entry!(
          directory: root.join("tmp/developer-mode/web-push"),
          now: now,
          entry: entry
        )

        Capture.new(capture_id: capture_id, path: path)
      rescue StandardError => error
        Rails.logger.error(
          "[DeveloperModeCapture] web push capture failed: #{error.class}: #{error.message}"
        )
        nil
      end

      private

      def append_entry!(directory:, now:, entry:)
        FileUtils.mkdir_p(directory)
        path = directory.join("#{now.utc.to_date.iso8601}.jsonl")
        File.open(path, File::WRONLY | File::APPEND | File::CREAT, 0o600) do |file|
          file.flock(File::LOCK_EX)
          file.puts(JSON.generate(entry))
          file.flush
        ensure
          file.flock(File::LOCK_UN)
        end
        path
      end

      def filtered_url(uri)
        copy = uri.dup
        copy.user = nil
        copy.password = nil
        copy.path = filtered_path(copy.path)
        copy.query = filtered_query(copy.query)
        copy.to_s
      end

      def filtered_path(path)
        value = path.to_s
        return value if value.blank? || value == "/"

        "/__filtered__"
      end

      def filtered_query(query)
        return nil if query.blank?

        parameters = URI.decode_www_form(query).to_h
        URI.encode_www_form(parameter_filter.filter(parameters))
      rescue ArgumentError
        FILTERED
      end

      def filtered_headers(headers)
        headers.to_h.to_h do |key, value|
          [ key.to_s, key.to_s.match?(SENSITIVE_HEADER) ? FILTERED : value.to_s ]
        end
      end

      def filtered_payload(body, additional_filters: [])
        parsed = JSON.parse(body.to_s)
        parameter_filter(additional_filters).filter(parsed)
      rescue JSON::ParserError
        {
          body_bytes: body.to_s.bytesize,
          body_sha256: Digest::SHA256.hexdigest(body.to_s)
        }
      end

      def parameter_filter(additional_filters = [])
        ActiveSupport::ParameterFilter.new(
          Rails.application.config.filter_parameters + additional_filters
        )
      end
    end
  end
end

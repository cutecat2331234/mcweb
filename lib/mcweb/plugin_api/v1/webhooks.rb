# frozen_string_literal: true

require "uri"
require "url_safety"
require_relative "outbound_support"

module Mcweb
  module PluginApi
    module V1
      class Webhooks
        include OutboundSupport

        READ_CAPABILITY = "plugin.webhooks.read"
        DELIVER_CAPABILITY = "plugin.webhooks.deliver"
        MAX_SECRET_BYTES = 4_096

        def initialize(plugin_id:, capability_auditor: nil)
          @plugin_id = plugin_id
          @capability_auditor = capability_auditor
          freeze
        end

        def deliver(
          url:,
          event:,
          data:,
          secret:,
          idempotency_key:,
          max_attempts: 5
        )
          audit(DELIVER_CAPABILITY)
          destination = url.to_s.strip
          unless UrlSafety.public_http_url?(destination)
            return Result.failure(code: "unsafe_url", error: "url must resolve to a public HTTP endpoint")
          end
          event, failure = normalize_type(event, field: "event")
          return failure if failure
          unless data.is_a?(Hash)
            return Result.failure(code: "invalid_argument", error: "data must be a mapping")
          end
          secret = secret.to_s
          unless secret.bytesize.between?(16, MAX_SECRET_BYTES)
            return Result.failure(
              code: "invalid_argument",
              error: "secret must be between 16 and #{MAX_SECRET_BYTES} bytes"
            )
          end

          enqueue_delivery(
            kind: "webhook",
            idempotency_key:,
            destination:,
            secret:,
            max_attempts:,
            payload: {
              schema_version: "1",
              event: "plugin.#{@plugin_id.tr('/_-', '.')}.#{event}",
              plugin_id: @plugin_id,
              data:
            }
          )
        end

        def find(public_id:)
          audit(READ_CAPABILITY)
          find_delivery(public_id:, kind: "webhook")
        end

        private

        def audit(capability)
          @capability_auditor&.call(capability)
        end
      end
    end
  end
end

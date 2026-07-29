# frozen_string_literal: true

module Mcweb
  module PluginApi
    module V1
      module OutboundDeliverySnapshot
        SCHEMA_VERSION = "1"

        module_function

        def call(delivery, idempotent: false)
          {
            schema_version: SCHEMA_VERSION,
            public_id: delivery.public_id,
            plugin_id: delivery.owner_plugin_id,
            kind: delivery.kind,
            status: delivery.status,
            attempts: delivery.attempts,
            max_attempts: delivery.max_attempts,
            next_attempt_at: delivery.next_attempt_at&.iso8601(6),
            last_http_status: delivery.last_http_status,
            last_error_code: delivery.last_error_code,
            response_summary: delivery.response_summary,
            delivered_at: delivery.delivered_at&.iso8601(6),
            created_at: delivery.created_at&.iso8601(6),
            updated_at: delivery.updated_at&.iso8601(6),
            idempotent:
          }.freeze
        end
      end
    end
  end
end

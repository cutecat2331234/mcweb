# frozen_string_literal: true

require_relative "outbound_support"

module Mcweb
  module PluginApi
    module V1
      class Notifications
        include OutboundSupport

        READ_CAPABILITY = "plugin.notifications.read"
        DELIVER_CAPABILITY = "plugin.notifications.deliver"

        def initialize(plugin_id:, capability_auditor: nil)
          @plugin_id = plugin_id
          @capability_auditor = capability_auditor
          freeze
        end

        def deliver(
          user:,
          notification_type:,
          title:,
          body: nil,
          metadata: {},
          idempotency_key:
        )
          audit(DELIVER_CAPABILITY)
          user, failure = resolve_recipient(user)
          return failure if failure
          type, failure = plugin_notification_type(notification_type)
          return failure if failure
          title, failure = normalize_text(title, field: "title", required: true, maximum: 255)
          return failure if failure
          body, failure = normalize_text(body, field: "body")
          return failure if failure
          unless metadata.is_a?(Hash)
            return Result.failure(code: "invalid_argument", error: "metadata must be a mapping")
          end

          enqueue_delivery(
            kind: "notification",
            idempotency_key:,
            user:,
            payload: {
              notification_type: type,
              title:,
              body: body.presence,
              metadata:
            }
          )
        end

        def find(public_id:)
          audit(READ_CAPABILITY)
          find_delivery(public_id:, kind: "notification")
        end

        private

        def audit(capability)
          @capability_auditor&.call(capability)
        end
      end
    end
  end
end

# frozen_string_literal: true

require_relative "outbound_support"

module Mcweb
  module PluginApi
    module V1
      class Mailer
        include OutboundSupport

        READ_CAPABILITY = "plugin.mail.read"
        DELIVER_CAPABILITY = "plugin.mail.deliver"

        def initialize(plugin_id:, capability_auditor: nil)
          @plugin_id = plugin_id
          @capability_auditor = capability_auditor
          freeze
        end

        def deliver(
          user:,
          notification_type:,
          subject:,
          text_body:,
          html_body: nil,
          idempotency_key:
        )
          audit(DELIVER_CAPABILITY)
          user, failure = resolve_recipient(user)
          return failure if failure
          type, failure = plugin_notification_type(notification_type)
          return failure if failure
          subject, failure = normalize_text(
            subject,
            field: "subject",
            required: true,
            maximum: 255
          )
          return failure if failure
          text_body, failure = normalize_text(
            text_body,
            field: "text_body",
            required: true
          )
          return failure if failure
          html_body, failure = normalize_text(html_body, field: "html_body")
          return failure if failure

          enqueue_delivery(
            kind: "mail",
            idempotency_key:,
            user:,
            payload: {
              notification_type: type,
              subject:,
              text_body:,
              html_body: html_body.presence
            }
          )
        end

        def find(public_id:)
          audit(READ_CAPABILITY)
          find_delivery(public_id:, kind: "mail")
        end

        private

        def audit(capability)
          @capability_auditor&.call(capability)
        end
      end
    end
  end
end

# frozen_string_literal: true

require_relative "result"
require_relative "../../events"

module Mcweb
  module PluginApi
    module V1
      class Events
        EVENT_PATTERN = /\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+\z/
        MAX_EVENT_NAME_LENGTH = 191

        def initialize(event_bus:, capability_auditor: nil)
          @event_bus = event_bus
          @capability_auditor = capability_auditor
          freeze
        end

        def catalog
          audit("forum.events.read")
          Result.success(Mcweb::Events::CATALOG)
        rescue StandardError => e
          Result.failure_from_exception(e)
        end

        def publish(name, payload = {})
          audit("forum.events.publish")
          event = name.to_s.dup.freeze
          unless event.length <= MAX_EVENT_NAME_LENGTH && event.match?(EVENT_PATTERN)
            return Result.failure(code: "invalid_argument", error: "invalid event name")
          end
          unless payload.is_a?(Hash)
            return Result.failure(code: "invalid_argument", error: "event payload must be a Hash")
          end

          @event_bus.publish(event, payload)
          Result.success(true)
        rescue StandardError => e
          Result.failure_from_exception(e, code: "event_publish_failed")
        end

        private

        def audit(capability)
          @capability_auditor&.call(capability)
        end
      end
    end
  end
end

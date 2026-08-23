# frozen_string_literal: true

module Minecraft
  class AppendWorldRestoreEvent < ApplicationService
    MAX_PAYLOAD_KEYS = 40
    MAX_STRING_LENGTH = 500

    def initialize(plan:, event_type:, phase:, actor: nil, payload: {})
      @plan = plan
      @event_type = event_type.to_s
      @phase = phase.to_s
      @actor = actor
      @payload = sanitize(payload.to_h.deep_stringify_keys)
    end

    def call
      @plan.with_lock do
        event = @plan.events.create!(
          sequence: @plan.events.maximum(:sequence).to_i + 1,
          event_type: @event_type,
          phase: @phase,
          actor: @actor,
          payload_summary: @payload,
          payload_digest: Minecraft::NodeOperationDigest.call(@payload),
          created_at: Time.current
        )
        ServiceResult.success(event: event)
      end
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    end

    private

    def sanitize(value)
      case value
      when Hash
        value.first(MAX_PAYLOAD_KEYS).to_h.transform_values { |child| sanitize(child) }
      when Array
        value.first(100).map { |child| sanitize(child) }
      when String
        value.first(MAX_STRING_LENGTH)
      when Time, ActiveSupport::TimeWithZone, DateTime
        value.iso8601(6)
      when Integer, Float, TrueClass, FalseClass, NilClass
        value
      else
        value.to_s.first(MAX_STRING_LENGTH)
      end
    end
  end
end

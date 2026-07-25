# frozen_string_literal: true

require "securerandom"
require "time"

module Mcweb
  module PluginApi
    module V1
      class Event
        SCHEMA_VERSION = "1"

        attr_reader :name, :event_id, :schema_version, :occurred_at, :data

        def self.build(name:, payload:)
          new(
            name:,
            event_id: SecureRandom.uuid,
            schema_version: SCHEMA_VERSION,
            occurred_at: Time.current.utc,
            data: Normalizer.call(payload)
          )
        end

        def initialize(name:, event_id:, schema_version:, occurred_at:, data:)
          @name = name.to_s.dup.freeze
          @event_id = event_id.to_s.dup.freeze
          @schema_version = schema_version.to_s.dup.freeze
          @occurred_at = occurred_at.dup.freeze
          @data = data
          freeze
        end

        def to_h
          {
            name: name,
            event_id: event_id,
            schema_version: schema_version,
            occurred_at: occurred_at.iso8601(6).freeze,
            data: data
          }.freeze
        end
      end
    end
  end
end

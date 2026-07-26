# frozen_string_literal: true

require_relative "normalizer"

module Mcweb
  module PluginApi
    module V1
      class JobContext
        SCHEMA_VERSION = "1"

        attr_reader :schema_version, :run_public_id, :owner_plugin_id, :job_key,
                    :attempt, :max_attempts, :scheduled_at

        def initialize(
          run_public_id:,
          owner_plugin_id:,
          job_key:,
          attempt:,
          max_attempts:,
          scheduled_at:
        )
          @schema_version = SCHEMA_VERSION
          @run_public_id = run_public_id.to_s.dup.freeze
          @owner_plugin_id = owner_plugin_id.to_s.dup.freeze
          @job_key = job_key.to_s.dup.freeze
          @attempt = Integer(attempt)
          @max_attempts = Integer(max_attempts)
          @scheduled_at = scheduled_at&.iso8601&.freeze
          freeze
        end

        def to_h
          {
            schema_version:,
            run_public_id:,
            owner_plugin_id:,
            job_key:,
            attempt:,
            max_attempts:,
            scheduled_at:
          }.freeze
        end
      end
    end
  end
end

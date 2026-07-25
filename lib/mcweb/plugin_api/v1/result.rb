# frozen_string_literal: true

require_relative "normalizer"

module Mcweb
  module PluginApi
    module V1
      # Immutable, versioned boundary result used by every host facade operation.
      # Active Record values are never retained: callers receive normalized
      # snapshots owned by the SDK.
      class Result
        SCHEMA_VERSION = "1"

        attr_reader :schema_version, :code, :value, :error, :errors

        def self.success(value = nil)
          new(success: true, code: "ok", value:)
        end

        def self.failure(code:, error: nil, errors: nil)
          new(success: false, code:, error:, errors:)
        end

        def self.failure_from_exception(exception, code: "host_error")
          failure(
            code:,
            error: "#{exception.class}: #{exception.message}"
          )
        end

        def self.from_service_result(service_result)
          if service_result.success?
            value = block_given? ? yield(service_result.value) : service_result.value
            success(value)
          else
            failure(
              code: "service_failure",
              error: service_result.error,
              errors: service_result.errors
            )
          end
        end

        def initialize(success:, code:, value: nil, error: nil, errors: nil)
          @success = success == true
          @schema_version = SCHEMA_VERSION
          @code = code.to_s.dup.freeze
          @value = Normalizer.call(value)
          @error = error.nil? ? nil : error.to_s.dup.freeze
          @errors = Normalizer.call(errors || {})
          freeze
        end

        def success?
          @success
        end

        def failure?
          !success?
        end

        def to_h
          {
            schema_version: schema_version,
            success: success?,
            code: code,
            value: value,
            error: error,
            errors: errors
          }.freeze
        end
      end
    end
  end
end

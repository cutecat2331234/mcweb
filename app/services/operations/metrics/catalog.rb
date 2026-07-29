# frozen_string_literal: true

require "bigdecimal"
require "digest"

module Operations
  module Metrics
    class Catalog
      MAX_VALUE = BigDecimal("1000000000000")

      SURFACES = %w[admin api app website other].freeze
      OUTCOMES = %w[success client_error server_error failure other].freeze
      QUEUES = %w[
        default mailers maintenance minecraft notifications payments plugins
        website other
      ].freeze
      PAYMENT_PROVIDERS = %w[fake stripe other].freeze
      PAYMENT_OUTCOMES = %w[
        processed retry_scheduled dead_letter other
      ].freeze
      UPLOAD_KINDS = %w[inline_image post_attachment other].freeze
      UPLOAD_EVENTS = %w[
        reserved stored quota_rejected cleaned cleanup_failed
        cleanup_retry_requested unattached_blob_cleaned other
      ].freeze
      SCAN_OUTCOMES = %w[clean infected error retry_requested other].freeze

      DEFINITIONS = {
        "request.duration_ms" => {
          "surface" => SURFACES,
          "outcome" => OUTCOMES
        },
        "request.server_error" => {
          "surface" => SURFACES
        },
        "database.slow_query.duration_ms" => {},
        "job.execution.duration_ms" => {
          "queue" => QUEUES,
          "outcome" => %w[success failure other].freeze
        },
        "job.failure" => {
          "queue" => QUEUES
        },
        "mail.delivery.duration_ms" => {
          "outcome" => %w[success failure other].freeze
        },
        "mail.failure" => {},
        "payments.webhook.processed" => {
          "provider" => PAYMENT_PROVIDERS,
          "outcome" => PAYMENT_OUTCOMES
        },
        "community.upload.event" => {
          "event" => UPLOAD_EVENTS,
          "kind" => UPLOAD_KINDS
        },
        "community.scan.event" => {
          "outcome" => SCAN_OUTCOMES
        },
        "queue.enqueued" => {},
        "queue.oldest_wait_seconds" => {},
        "queue.utilization_percent" => {},
        "queue.worker_count" => {}
      }.transform_values(&:freeze).freeze

      Normalized = Data.define(
        :metric_name,
        :dimensions,
        :dimensions_key,
        :value
      )

      class << self
        def normalize(metric_name, value:, dimensions:)
          name = metric_name.to_s
          definition = DEFINITIONS.fetch(name)
          normalized_dimensions = normalize_dimensions(
            definition,
            dimensions
          )
          normalized_value = normalize_value(value)
          canonical = JSON.generate(normalized_dimensions)

          Normalized.new(
            metric_name: name,
            dimensions: normalized_dimensions.freeze,
            dimensions_key: Digest::SHA256.hexdigest(canonical),
            value: normalized_value
          )
        end

        private

        def normalize_dimensions(definition, dimensions)
          source = dimensions.to_h.stringify_keys
          definition.keys.sort.to_h do |key|
            allowed = definition.fetch(key)
            candidate = source[key].to_s
            [ key, allowed.include?(candidate) ? candidate : "other" ]
          end
        end

        def normalize_value(value)
          parsed = BigDecimal(value.to_s)
          raise ArgumentError, "metric value must be finite" unless parsed.finite?

          parsed.clamp(0, MAX_VALUE).round(6)
        rescue TypeError, ArgumentError
          raise ArgumentError, "metric value must be numeric"
        end
      end
    end
  end
end

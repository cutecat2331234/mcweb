# frozen_string_literal: true

require "bigdecimal"
require "digest"
require Rails.root.join("lib/mcweb/operations_metrics_registrar_config")

module Operations
  module Metrics
    class Catalog
      MAX_VALUE = BigDecimal("1000000000000")

      SURFACES = %w[admin api app website health other].freeze
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
        "request.total_duration_ms" => {
          "surface" => SURFACES,
          "outcome" => OUTCOMES
        },
        "request.queue_duration_ms" => {
          "surface" => SURFACES
        },
        "request.middleware_duration_ms" => {
          "surface" => SURFACES
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

      DEFINITION_TYPES = {
        "request.duration_ms" => "distribution",
        "request.total_duration_ms" => "distribution",
        "request.queue_duration_ms" => "distribution",
        "request.middleware_duration_ms" => "distribution",
        "request.server_error" => "counter",
        "database.slow_query.duration_ms" => "distribution",
        "job.execution.duration_ms" => "distribution",
        "job.failure" => "counter",
        "mail.delivery.duration_ms" => "distribution",
        "mail.failure" => "counter",
        "payments.webhook.processed" => "counter",
        "community.upload.event" => "counter",
        "community.scan.event" => "counter",
        "queue.enqueued" => "gauge",
        "queue.oldest_wait_seconds" => "gauge",
        "queue.utilization_percent" => "gauge",
        "queue.worker_count" => "gauge"
      }.freeze

      Normalized = Data.define(
        :metric_name,
        :dimensions,
        :dimensions_key,
        :value
      )

      class << self
        def finalize!
          return @registry if @boot_finalized == true
          if Rails.application.initialized? && !registration_closed?
            raise FrozenError, "operations_metrics_catalog_boot_closed"
          end

          finalization_mutex.synchronize do
            return @registry if @boot_finalized == true

            candidate = build_registry
            @registry = candidate
            @boot_finalized = true
          end
          @registry
        end

        def registry_frozen?
          @boot_finalized == true && @registry&.frozen? == true
        end

        def metric_names
          registry.keys
        end

        def definition(metric_name)
          registry.entry(metric_name)
        end

        def registered?(metric_name)
          !definition(metric_name).nil?
        end

        def normalize(metric_name, value:, dimensions:)
          name = metric_name.to_s
          definition = registry.fetch(name).dimensions
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

        def registry
          ensure_finalized!
          @registry
        end

        def ensure_finalized!
          return if @boot_finalized == true

          raise FrozenError, "operations_metrics_catalog_not_boot_finalized"
        end

        def build_registry
          candidate = ::Operations::Metrics::Registry.new
          DEFINITIONS.each do |key, dimensions|
            candidate.register(
              key:,
              type: DEFINITION_TYPES.fetch(key),
              dimensions:
            )
          end
          configured_registrars.each { |registrar| registrar.call(candidate) }
          candidate.freeze!
        end

        def configured_registrars
          Mcweb::OperationsMetricsRegistrarConfig.freeze_and_fetch!(
            Rails.application.config.x
          )
        end

        def registration_closed?
          Mcweb::OperationsMetricsRegistrarConfig.registration_closed?(
            Rails.application.config.x
          )
        end

        def finalization_mutex
          @finalization_mutex ||= Mutex.new
        end

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

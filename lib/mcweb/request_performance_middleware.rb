# frozen_string_literal: true

module Mcweb
  class RequestPerformanceMiddleware
    ACTION_DURATION_KEY = :mcweb_operations_metrics_action_duration_ms
    REQUEST_START_HEADERS = %w[
      HTTP_X_REQUEST_START
      HTTP_X_QUEUE_START
    ].freeze
    MAX_QUEUE_DURATION_MS = 600_000

    def initialize(
      app,
      monotonic_clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
      wall_clock: -> { Time.now.to_f }
    )
      @app = app
      @monotonic_clock = monotonic_clock
      @wall_clock = wall_clock
    end

    def call(environment)
      started_at = @monotonic_clock.call
      queue_duration_ms = queue_duration(environment)
      ActiveSupport::IsolatedExecutionState[ACTION_DURATION_KEY] = nil

      status, headers, body = @app.call(environment)
      rack_duration_ms = elapsed_ms(started_at)
      total_duration_ms = (queue_duration_ms + rack_duration_ms).round(3)
      action_duration_ms =
        ActiveSupport::IsolatedExecutionState[ACTION_DURATION_KEY]
      middleware_duration_ms = action_duration_ms &&
        [ rack_duration_ms - action_duration_ms, 0 ].max

      append_server_timing!(
        headers,
        queue_duration_ms:,
        middleware_duration_ms:,
        rack_duration_ms:,
        total_duration_ms:
      )
      publish(
        environment,
        status:,
        duration_ms: total_duration_ms,
        rack_duration_ms:,
        queue_duration_ms:,
        middleware_duration_ms:
      )
      [ status, headers, body ]
    rescue Exception # rubocop:disable Lint/RescueException
      rack_duration_ms = elapsed_ms(started_at)
      publish(
        environment,
        status: 500,
        duration_ms: (queue_duration_ms.to_f + rack_duration_ms).round(3),
        rack_duration_ms:,
        queue_duration_ms: queue_duration_ms || 0.0,
        middleware_duration_ms: nil
      )
      raise
    ensure
      ActiveSupport::IsolatedExecutionState[ACTION_DURATION_KEY] = nil
    end

    private

    def queue_duration(environment)
      raw = REQUEST_START_HEADERS.filter_map do |key|
        value = environment[key].to_s.strip
        value unless value.empty?
      end.first
      return 0.0 unless raw

      timestamp = Float(raw.delete_prefix("t="), exception: false)
      return 0.0 unless timestamp&.positive?

      timestamp /= 1_000.0 if timestamp > 10_000_000_000
      duration = (@wall_clock.call - timestamp) * 1_000.0
      return 0.0 unless duration.between?(0, MAX_QUEUE_DURATION_MS)

      duration.round(3)
    end

    def elapsed_ms(started_at)
      ((@monotonic_clock.call - started_at) * 1_000.0).round(3)
    end

    def append_server_timing!(
      headers,
      queue_duration_ms:,
      middleware_duration_ms:,
      rack_duration_ms:,
      total_duration_ms:
    )
      values = []
      values << "queue;dur=#{queue_duration_ms}" if queue_duration_ms.positive?
      values << "middleware;dur=#{middleware_duration_ms}" if middleware_duration_ms
      values << "rack;dur=#{rack_duration_ms}"
      values << "total;dur=#{total_duration_ms}"
      existing = headers["Server-Timing"].to_s.strip
      values.unshift(existing) unless existing.empty?
      headers["Server-Timing"] = values.join(", ")
    end

    def publish(
      environment,
      status:,
      duration_ms:,
      rack_duration_ms:,
      queue_duration_ms:,
      middleware_duration_ms:
    )
      ActiveSupport::Notifications.instrument(
        "mcweb.request.outer",
        status:,
        duration_ms:,
        rack_duration_ms:,
        queue_duration_ms:,
        middleware_duration_ms:,
        surface: surface_for(environment["PATH_INFO"])
      )
    rescue StandardError => error
      ::Operations::Metrics.report_failure("outer request ignored", error) if
        defined?(::Operations::Metrics)
    end

    def surface_for(path)
      case path.to_s
      when %r{\A/admin(?:/|\z)} then "admin"
      when %r{\A/api(?:/|\z)} then "api"
      when %r{\A/app(?:/|\z)} then "app"
      when "/up", "/live", "/ready" then "health"
      when %r{\A/(?:\z|about|blog|pages|identity)} then "website"
      else "other"
      end
    end
  end
end

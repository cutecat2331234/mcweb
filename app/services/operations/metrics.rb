# frozen_string_literal: true

module Operations
  module Metrics
    SILENCE_KEY = :mcweb_operations_metrics_silenced
    DIAGNOSTIC_INTERVAL = 1.minute
    DIAGNOSTIC_BACKTRACE_LINES = 5

    class << self
      attr_writer :buffer

      def buffer
        @buffer ||= ::Operations::Metrics::Buffer.new
      end

      def record(metric_name, value: 1, dimensions: {}, at: Time.current)
        return false if silenced?

        buffer.record(
          metric_name,
          value:,
          dimensions:,
          at:
        )
      rescue StandardError => error
        report_failure("sample ignored", error)
        false
      end

      def flush!(now: Time.current)
        buffer.flush!(now:)
      end

      def silenced?
        ActiveSupport::IsolatedExecutionState[SILENCE_KEY] == true
      end

      def silence
        previous = ActiveSupport::IsolatedExecutionState[SILENCE_KEY]
        ActiveSupport::IsolatedExecutionState[SILENCE_KEY] = true
        yield
      ensure
        ActiveSupport::IsolatedExecutionState[SILENCE_KEY] = previous
      end

      def reset!
        @buffer = nil
        @diagnostic_log_at = {}
      end

      def report_failure(scope, error, logger: Rails.logger)
        return false unless diagnostic_log_due?(scope, error)

        message = sanitized_error_message(error.message)
        application_root = defined?(Rails) ? Rails.root.to_s.tr("\\", "/") : nil
        frames = Array(error.backtrace).filter_map do |frame|
          normalized = frame.to_s.tr("\\", "/")
          next if application_root && !normalized.start_with?(application_root)

          normalized.slice(0, 320)
        end.first(DIAGNOSTIC_BACKTRACE_LINES)
        detail = "#{error.class.name}: #{message}"
        detail = "#{detail} | #{frames.join(' <- ')}" if frames.any?
        logger.warn("[operations.metrics] #{scope}: #{detail}")
        true
      end

      private

      def diagnostic_log_due?(scope, error)
        @diagnostic_mutex ||= Mutex.new
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        key = [ scope.to_s, error.class.name, sanitized_error_message(error.message) ]
        @diagnostic_mutex.synchronize do
          @diagnostic_log_at ||= {}
          previous = @diagnostic_log_at[key]
          return false if previous && now - previous < DIAGNOSTIC_INTERVAL

          @diagnostic_log_at[key] = now
          @diagnostic_log_at.delete_if do |_entry_key, timestamp|
            now - timestamp >= DIAGNOSTIC_INTERVAL
          end
          true
        end
      end

      def sanitized_error_message(message)
        message.to_s
          .gsub(/[\r\n]+/, " ")
          .gsub(
            /\b(password|token|secret|authorization|cookie)\s*[:=]\s*[^\s,;]+/i,
            '\\1=[FILTERED]'
          )
          .slice(0, 240)
      end
    end
  end
end

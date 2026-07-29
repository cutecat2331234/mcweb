# frozen_string_literal: true

module Operations
  module Metrics
    SILENCE_KEY = :mcweb_operations_metrics_silenced

    class << self
      attr_writer :buffer

      def buffer
        @buffer ||= Buffer.new
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
        Rails.logger.warn(
          "[operations.metrics] sample ignored: #{error.class.name}"
        )
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
      end
    end
  end
end

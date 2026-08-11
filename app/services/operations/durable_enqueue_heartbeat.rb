# frozen_string_literal: true

module Operations
  class DurableEnqueueHeartbeat
    STOP_JOIN_TIMEOUT = 5

    def initialize(context:, interval:)
      interval = Float(interval, exception: false)
      raise ArgumentError, "interval must be finite and positive" unless interval&.finite? && interval.positive?

      @context = context
      @interval = interval
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @stopped = false
    end

    def start
      @thread = Thread.new do
        Thread.current.report_on_exception = false
        Rails.application.executor.wrap do
          loop do
            break if wait_until_tick_or_stop

            result = @context.heartbeat!
            break if result.failure? || (result.success? && result.value.to_h[:skipped])
          rescue StandardError => error
            Rails.logger.warn(
              "[operations.durable_enqueue] heartbeat_failed " \
              "intent=#{@context.intent_public_id} error=#{error.class}"
            )
          end
        end
      end
      self
    end

    def stop
      @mutex.synchronize do
        @stopped = true
        @condition.broadcast
      end
      return unless @thread
      return if @thread.join(STOP_JOIN_TIMEOUT)

      Rails.logger.warn(
        "[operations.durable_enqueue] heartbeat_stop_timeout " \
        "intent=#{@context.intent_public_id}"
      )
    end

    private

    def wait_until_tick_or_stop
      @mutex.synchronize do
        @condition.wait(@mutex, @interval) unless @stopped
        @stopped
      end
    end
  end
end

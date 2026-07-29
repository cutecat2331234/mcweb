# frozen_string_literal: true

module Operations
  class FlushMetricsJob < ApplicationJob
    class FlushFailed < StandardError; end

    queue_as :maintenance
    retry_on FlushFailed, wait: 30.seconds, attempts: 3

    class_attribute :queue_snapshot_factory,
      instance_writer: false,
      default: -> { QueueSnapshot.call }

    def perform(now: Time.current)
      record_queue_snapshot(now)
      result = Metrics.flush!(now:)
      raise FlushFailed, "Operations metrics flush failed." if result == false

      result
    end

    private

    def record_queue_snapshot(now)
      result = queue_snapshot_factory.call
      snapshot = result.value
      return unless snapshot.fetch(:available, false)

      {
        "queue.enqueued" => snapshot.fetch(:enqueued, 0),
        "queue.oldest_wait_seconds" =>
          snapshot.fetch(:oldest_wait_seconds, 0),
        "queue.utilization_percent" =>
          snapshot.fetch(:utilization_percent, 0),
        "queue.worker_count" => snapshot.fetch(:worker_count, 0)
      }.each do |metric_name, value|
        Metrics.record(metric_name, value:, at: now)
      end
    rescue StandardError => error
      Rails.logger.warn(
        "[operations.metrics] queue sample unavailable: #{error.class.name}"
      )
    end
  end
end

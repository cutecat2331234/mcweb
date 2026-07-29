# frozen_string_literal: true

require "sidekiq/api"

module Operations
  class QueueSnapshot < ApplicationService
    DEFAULT_BACKLOG_WARNING = 1_000
    DEFAULT_LATENCY_WARNING_SECONDS = 300

    def initialize(
      queue_adapter: Rails.application.config.active_job.queue_adapter,
      production: Rails.env.production?,
      stats: nil,
      processes: nil,
      queues: nil,
      backlog_warning: ENV.fetch(
        "MCWEB_QUEUE_BACKLOG_WARNING",
        DEFAULT_BACKLOG_WARNING
      ).to_i,
      latency_warning_seconds: ENV.fetch(
        "MCWEB_QUEUE_LATENCY_WARNING_SECONDS",
        DEFAULT_LATENCY_WARNING_SECONDS
      ).to_i
    )
      @queue_adapter = queue_adapter.to_sym
      @production = production
      @stats = stats
      @processes = processes
      @queues = queues
      @backlog_warning = [ backlog_warning, 1 ].max
      @latency_warning_seconds = [ latency_warning_seconds, 1 ].max
    end

    def call
      return non_sidekiq_snapshot unless @queue_adapter == :sidekiq

      stats = @stats || Sidekiq::Stats.new
      processes = Array(@processes || Sidekiq::ProcessSet.new(false).to_a)
      queues = Array(@queues || Sidekiq::Queue.all)
      queue_rows = queues.map { |queue| serialize_queue(queue) }
        .sort_by { |queue| [ -queue.fetch(:latency_seconds), queue.fetch(:name) ] }
      enqueued = integer_value(stats, :enqueued)
      oldest_wait = queue_rows
        .map { |queue| queue.fetch(:latency_seconds) }
        .max
        .to_f
        .round(3)
      worker_count = processes.length
      busy = processes.sum { |process| process_value(process, "busy").to_i }
      concurrency = processes.sum do |process|
        process_value(process, "concurrency").to_i
      end
      utilization = utilization_percent(busy:, concurrency:)
      dead_count = integer_value(stats, :dead_size)
      status = status_for(
        worker_count:,
        enqueued:,
        oldest_wait:,
        dead_count:,
        utilization:
      )

      ServiceResult.success(
        available: true,
        adapter: "sidekiq",
        status:,
        worker_count:,
        busy_workers: busy,
        concurrency:,
        utilization_percent: utilization,
        enqueued:,
        retry_count: integer_value(stats, :retry_size),
        scheduled_count: integer_value(stats, :scheduled_size),
        dead_count:,
        failed_count: integer_value(stats, :failed),
        processed_count: integer_value(stats, :processed),
        oldest_wait_seconds: oldest_wait,
        backlog_warning: @backlog_warning,
        latency_warning_seconds: @latency_warning_seconds,
        queues: queue_rows
      )
    rescue StandardError => error
      Rails.logger.warn(
        "[operations.queue_snapshot] unavailable: #{error.class.name}"
      )
      ServiceResult.success(
        available: false,
        adapter: @queue_adapter.to_s,
        status: "unavailable",
        error_code: "queue_snapshot_unavailable",
        worker_count: 0,
        busy_workers: 0,
        concurrency: 0,
        utilization_percent: 0.0,
        enqueued: 0,
        retry_count: 0,
        scheduled_count: 0,
        dead_count: 0,
        failed_count: 0,
        processed_count: 0,
        oldest_wait_seconds: 0.0,
        backlog_warning: @backlog_warning,
        latency_warning_seconds: @latency_warning_seconds,
        queues: []
      )
    end

    private

    def non_sidekiq_snapshot
      ServiceResult.success(
        available: true,
        adapter: @queue_adapter.to_s,
        status: "local",
        worker_count: 0,
        busy_workers: 0,
        concurrency: 0,
        utilization_percent: 0.0,
        enqueued: 0,
        retry_count: 0,
        scheduled_count: 0,
        dead_count: 0,
        failed_count: 0,
        processed_count: 0,
        oldest_wait_seconds: 0.0,
        backlog_warning: @backlog_warning,
        latency_warning_seconds: @latency_warning_seconds,
        queues: []
      )
    end

    def serialize_queue(queue)
      {
        name: queue_value(queue, :name).to_s.slice(0, 128),
        size: queue_value(queue, :size).to_i,
        latency_seconds: queue_value(queue, :latency).to_f.round(3)
      }.freeze
    end

    def status_for(worker_count:, enqueued:, oldest_wait:, dead_count:,
                   utilization:)
      return "error" if @production && worker_count.zero?
      return "warning" if dead_count.positive?
      return "warning" if enqueued >= @backlog_warning
      return "warning" if oldest_wait >= @latency_warning_seconds
      return "warning" if utilization >= 90

      "healthy"
    end

    def utilization_percent(busy:, concurrency:)
      return 0.0 if concurrency.zero?

      ((busy.to_f / concurrency) * 100).clamp(0, 100).round(1)
    end

    def integer_value(object, key)
      object.public_send(key).to_i
    rescue NoMethodError
      0
    end

    def queue_value(queue, key)
      queue.public_send(key)
    rescue NoMethodError
      queue[key.to_s] || queue[key]
    end

    def process_value(process, key)
      process[key] || process[key.to_sym]
    rescue NoMethodError, TypeError
      nil
    end
  end
end

# frozen_string_literal: true

require "digest"
require "sidekiq/api"
require "stringio"

module Operations
  class HealthChecker < ApplicationService
    STORAGE_PROBE_PREFIX = "health/readiness-probes"
    STORAGE_PROBE_PAYLOAD = "mcweb-storage-readiness-v1".b.freeze
    CRITICAL_CHECKS = %i[database queue storage].freeze

    def initialize(
      queue_adapter: Rails.application.config.active_job.queue_adapter,
      production: Rails.env.production?,
      sidekiq_stats: nil,
      sidekiq_processes: nil,
      sidekiq_queues: nil,
      worker_heartbeat_at: :auto,
      clock: -> { Time.current },
      storage_service: nil
    )
      @queue_adapter = queue_adapter
      @production = production
      @sidekiq_stats = sidekiq_stats
      @sidekiq_processes = sidekiq_processes
      @sidekiq_queues = sidekiq_queues
      @worker_heartbeat_at = worker_heartbeat_at
      @clock = clock
      @storage_service = storage_service
    end

    def call
      checks = {
        database: check_database,
        queue: check_queue,
        storage: check_storage,
        minecraft_nodes: check_minecraft_nodes
      }

      healthy = CRITICAL_CHECKS.all? { |key| checks.fetch(key)[:status] == "ok" }
      ServiceResult.success(status: healthy ? "ok" : "degraded", checks: checks)
    end

    private

    def check_database
      ActiveRecord::Base.lease_connection.execute("SELECT 1")
      { status: "ok" }
    rescue StandardError => e
      failed_check("database_unavailable", e)
    end

    def check_queue
      adapter = @queue_adapter
      if adapter == :sidekiq
        snapshot = QueueSnapshot.call(
          queue_adapter: adapter,
          production: @production,
          stats: @sidekiq_stats,
          processes: @sidekiq_processes,
          queues: @sidekiq_queues
        ).value
        attach_worker_heartbeat(queue_health_payload(snapshot))
      else
        { status: "ok", pending_jobs: 0, failed_jobs: 0, adapter: adapter.to_s }
      end
    rescue StandardError => e
      failed_check("queue_unavailable", e)
    end

    def check_storage
      service = @storage_service || ActiveStorage::Blob.service
      key = "#{STORAGE_PROBE_PREFIX}/#{SecureRandom.uuid}"
      failure = nil
      downloaded = nil

      begin
        service.upload(
          key,
          StringIO.new(STORAGE_PROBE_PAYLOAD),
          checksum: Digest::MD5.base64digest(STORAGE_PROBE_PAYLOAD)
        )
        downloaded = service.download(key)
        unless downloaded == STORAGE_PROBE_PAYLOAD
          raise ActiveStorage::IntegrityError, "storage readiness payload mismatch"
        end
      rescue StandardError => e
        failure = e
      ensure
        begin
          service.delete(key)
        rescue StandardError => e
          failure ||= e
        end
      end

      return failed_check("storage_unavailable", failure) if failure

      {
        status: "ok",
        service: service.class.name.to_s.demodulize,
        probe: "write_read_delete"
      }
    end

    def queue_health_payload(snapshot)
      payload = {
        pending_jobs: snapshot.fetch(:enqueued),
        failed_jobs: snapshot.fetch(:failed_count),
        adapter: snapshot.fetch(:adapter),
        worker_processes: snapshot.fetch(:worker_count),
        busiest_workers: snapshot.fetch(:busy_workers),
        concurrency: snapshot.fetch(:concurrency),
        utilization_percent: snapshot.fetch(:utilization_percent),
        oldest_wait_seconds: snapshot.fetch(:oldest_wait_seconds),
        retry_jobs: snapshot.fetch(:retry_count),
        dead_jobs: snapshot.fetch(:dead_count)
      }
      return payload.merge(status: "ok") if snapshot.fetch(:status) == "healthy"

      payload.merge(
        status: "error",
        error_code: queue_error_code(snapshot)
      )
    end

    def attach_worker_heartbeat(payload)
      return payload unless @production

      heartbeat_at = latest_worker_heartbeat_at
      payload = payload.merge(
        last_worker_heartbeat_at: heartbeat_at&.iso8601
      )
      return payload unless payload.fetch(:status) == "ok"
      return payload if heartbeat_at &&
        heartbeat_at >= @clock.call - WorkerHeartbeat::FRESH_FOR

      payload.merge(
        status: "error",
        error_code: "worker_heartbeat_stale"
      )
    end

    def latest_worker_heartbeat_at
      return @worker_heartbeat_at unless @worker_heartbeat_at == :auto

      WorkerHeartbeat.sidekiq.maximum(:last_seen_at)
    end

    def queue_error_code(snapshot)
      return "queue_unavailable" unless snapshot.fetch(:available)
      return "worker_unavailable" if
        @production && snapshot.fetch(:worker_count).zero?
      return "queue_dead_jobs" if snapshot.fetch(:dead_count).positive?
      return "queue_backlog" if
        snapshot.fetch(:enqueued) >= snapshot.fetch(:backlog_warning)
      return "queue_latency" if
        snapshot.fetch(:oldest_wait_seconds) >=
          snapshot.fetch(:latency_warning_seconds)

      "queue_saturated"
    end

    def check_minecraft_nodes
      stale_nodes = Minecraft::Node.where(status: :online)
        .where("last_heartbeat_at IS NULL OR last_heartbeat_at < ?", 3.minutes.ago).count
      mismatched = Minecraft::Server.managed_by_node.where("metadata ? 'process_mismatch_alert'").count

      if stale_nodes.positive? || mismatched.positive?
        {
          status: "degraded",
          stale_online_nodes: stale_nodes,
          process_mismatch_servers: mismatched
        }
      else
        { status: "ok", nodes: Minecraft::Node.count, managed_servers: Minecraft::Server.managed_by_node.count }
      end
    rescue StandardError => e
      failed_check("minecraft_nodes_unavailable", e)
    end

    def failed_check(error_code, error)
      {
        status: "error",
        error_code: error_code,
        error_class: error.class.name
      }
    end
  end
end

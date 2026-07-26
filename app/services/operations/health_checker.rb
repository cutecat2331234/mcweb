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
      storage_service: nil
    )
      @queue_adapter = queue_adapter
      @production = production
      @sidekiq_stats = sidekiq_stats
      @sidekiq_processes = sidekiq_processes
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
        stats = @sidekiq_stats || Sidekiq::Stats.new
        processes = @sidekiq_processes || Sidekiq::ProcessSet.new(false).to_a
        if @production && processes.empty?
          return {
            status: "error",
            error_code: "worker_unavailable",
            adapter: "sidekiq",
            worker_processes: 0
          }
        end

        {
          status: "ok",
          pending_jobs: stats.enqueued,
          failed_jobs: stats.failed,
          adapter: "sidekiq",
          worker_processes: processes.length,
          busiest_workers: processes.sum { |process| process["busy"].to_i }
        }
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

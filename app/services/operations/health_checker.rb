# frozen_string_literal: true

module Operations
  class HealthChecker < ApplicationService
    def call
      checks = {
        database: check_database,
        queue: check_queue,
        storage: check_storage,
        minecraft_nodes: check_minecraft_nodes
      }

      healthy = checks.values.all? { |check| check[:status] == "ok" }
      ServiceResult.success(status: healthy ? "ok" : "degraded", checks: checks)
    end

    private

    def check_database
      ActiveRecord::Base.connection.execute("SELECT 1")
      { status: "ok" }
    rescue StandardError => e
      { status: "error", message: e.message }
    end

    def check_queue
      adapter = Rails.application.config.active_job.queue_adapter
      if adapter == :sidekiq
        stats = Sidekiq::Stats.new
        { status: "ok", pending_jobs: stats.enqueued, failed_jobs: stats.failed, adapter: "sidekiq" }
      else
        { status: "ok", pending_jobs: 0, failed_jobs: 0, adapter: adapter.to_s }
      end
    rescue StandardError => e
      { status: "error", message: e.message }
    end

    def check_storage
      ActiveStorage::Blob.limit(1).pick(:id)
      { status: "ok" }
    rescue StandardError => e
      { status: "error", message: e.message }
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
      { status: "error", message: e.message }
    end
  end
end

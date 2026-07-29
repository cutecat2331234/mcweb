# frozen_string_literal: true

module Admin
  module System
    class JobsController < BaseController
      before_action -> { require_permission("system.jobs.read") }

      class_attribute :queue_snapshot_factory,
        instance_writer: false,
        default: -> { Operations::QueueSnapshot.call }
      class_attribute :metrics_query_factory,
        instance_writer: false,
        default: ->(range:) {
          Operations::Metrics::TrendQuery.call(range:)
        }

      def index
        developer_mode_enabled = Mcweb::DeveloperMode.enabled?
        queue_result = queue_snapshot_factory.call
        render inertia: "Admin/System/Jobs/Index", props: {
          dashboardUrl: "/jobs",
          metricsUrl: admin_system_jobs_path,
          developerMode: {
            enabled: developer_mode_enabled,
            profile: developer_mode_enabled ?
              Mcweb::DeveloperMode.profile.to_s :
              nil
          },
          automaticRegistration:
            Mcweb::SidekiqCronSchedule.automatic_registration_enabled?,
          queueSnapshot: queue_result.value,
          workerHeartbeat: worker_heartbeat_snapshot,
          operationsMetrics: metrics_query_factory.call(
            range: params[:range].to_s
          )
        }
      end

      private

      def worker_heartbeat_snapshot
        unless ActiveRecord::Base.connection.data_source_exists?(
          "operations_worker_heartbeats"
        )
          return {
            available: false,
            status: "unavailable",
            fresh_count: 0,
            latest_at: nil
          }
        end

        now = Time.current
        latest_at = Operations::WorkerHeartbeat.sidekiq.maximum(:last_seen_at)
        fresh_count = Operations::WorkerHeartbeat.sidekiq.fresh(now).count
        status = if latest_at.nil?
          "missing"
        elsif latest_at >= now - Operations::WorkerHeartbeat::FRESH_FOR
          "healthy"
        else
          "stale"
        end
        {
          available: true,
          status:,
          fresh_count:,
          latest_at: latest_at&.iso8601
        }
      rescue ActiveRecord::ActiveRecordError
        {
          available: false,
          status: "unavailable",
          fresh_count: 0,
          latest_at: nil
        }
      end
    end
  end
end

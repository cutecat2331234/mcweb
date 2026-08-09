# frozen_string_literal: true

module Admin
  module System
    class JobsController < BaseController
      before_action -> { require_permission("system.jobs.read") }, only: :index
      before_action -> { require_permission("system.jobs.manage") }, only: :run

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
          manualTaskRunUrl: run_admin_system_jobs_path,
          manualTasks: manual_task_catalog,
          manualTaskRuns: recent_manual_task_runs,
          queueSnapshot: queue_result.value,
          workerHeartbeat: worker_heartbeat_snapshot,
          operationsMetrics: metrics_query_factory.call(
            range: params[:range].to_s
          )
        }
      end

      def run
        arguments = manual_task_arguments
        result = Operations::EnqueueManualTask.call(
          task_key: params[:task_key],
          actor: current_user,
          arguments: arguments,
          idempotency_key: params[:idempotency_key].presence || request.request_id,
          audit_context: {
            request_id: request.request_id,
            ip_address: request.remote_ip,
            user_agent: request.user_agent
          }
        )

        if result.success?
          redirect_to admin_system_jobs_path,
            notice: t("mcweb.flash.manual_task_enqueued")
        else
          redirect_to admin_system_jobs_path,
            alert: t("mcweb.flash.manual_task_rejected")
        end
      rescue Operations::ManualTaskCatalog::InvalidTask
        redirect_to admin_system_jobs_path,
          alert: t("mcweb.flash.manual_task_rejected")
      end

      private

      def manual_task_arguments
        entry = Operations::ManualTaskCatalog.entry(params[:task_key])
        return {} unless entry

        raw_arguments = params[:arguments]
        return {} if raw_arguments.blank?
        unless raw_arguments.is_a?(ActionController::Parameters)
          raise Operations::ManualTaskCatalog::InvalidTask, "unsupported_arguments"
        end

        allowed_keys = entry.argument_schema.keys
        unknown_keys = raw_arguments.keys.map(&:to_s) - allowed_keys
        if unknown_keys.any?
          raise Operations::ManualTaskCatalog::InvalidTask, "unsupported_arguments"
        end

        scalar_keys = allowed_keys.map(&:to_sym)
        list_filters = entry.argument_schema.filter_map do |key, schema|
          { key => [] } if schema.fetch(:type) == "integer_list"
        end
        raw_arguments.permit(*scalar_keys, *list_filters).to_h.compact_blank
      end

      def manual_task_catalog
        Operations::ManualTaskCatalog.entries_for(current_user).map do |entry|
          {
            key: entry.key,
            labelKey: entry.label_key,
            descriptionKey: entry.description_key,
            arguments: entry.argument_schema.map do |key, schema|
              {
                key:,
                type: schema.fetch(:type),
                required: schema.fetch(:required, false),
                minimum: schema[:minimum],
                maximumItems: schema[:maximum_items],
                labelKey: schema[:label_key],
                helpKey: schema[:help_key]
              }.compact
            end
          }
        end
      end

      def recent_manual_task_runs
        return [] unless ActiveRecord::Base.connection.data_source_exists?(
          "operations_manual_task_runs"
        )

        Operations::ManualTaskRun.recent_first.limit(25).map do |run|
          {
            id: run.id,
            taskKey: run.task_key,
            status: run.status,
            requestedBy: run.requested_by&.display_name,
            requestedAt: run.requested_at&.iso8601,
            startedAt: run.started_at&.iso8601,
            finishedAt: run.finished_at&.iso8601,
            errorCode: run.error_code
          }
        end
      rescue ActiveRecord::ActiveRecordError
        []
      end

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

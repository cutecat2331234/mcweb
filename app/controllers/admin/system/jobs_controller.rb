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
        redis_recovery = Operations::RedisQueueRecoverySnapshot.call(
          queue_snapshot: queue_result.value
        ).value
        render inertia: "Admin/System/Jobs/Index", props: {
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
          securityRecoveryDeliveries: recent_security_recovery_deliveries,
          securityRecoveryCopy: security_recovery_copy,
          queueSnapshot: queue_result.value,
          redisRecovery: redis_recovery,
          redisRecoveryCopy: redis_recovery_copy,
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
          { key => [] } if schema.fetch(:type).in?(%w[integer_list uuid_list])
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
                maximum: schema[:maximum],
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
            errorCode: run.error_code,
            result: safe_manual_task_result(run)
          }
        end
      rescue ActiveRecord::ActiveRecordError
        []
      end

      def recent_security_recovery_deliveries
        return [] unless ActiveRecord::Base.connection.data_source_exists?(
          "operations_durable_enqueue_intents"
        )

        Identity::SecurityRecoveryMailDelivery.recent_statuses(limit: 25).map do |delivery|
          {
            publicId: delivery.fetch(:public_id),
            userId: delivery.fetch(:user_id),
            purpose: delivery.fetch(:purpose),
            status: delivery.fetch(:status),
            durableStatus: delivery.fetch(:durable_status),
            retryable: delivery.fetch(:retryable),
            attemptCount: delivery.fetch(:attempt_count),
            requestedAt: delivery[:requested_at]&.iso8601,
            lastEventAt: delivery[:last_event_at]&.iso8601,
            reasonCode: delivery[:reason_code]
          }
        end
      rescue ActiveRecord::ActiveRecordError
        []
      end

      def security_recovery_copy
        scope = "mcweb.admin.jobs.security_recovery"
        {
          title: t("#{scope}.title"),
          description: t("#{scope}.description"),
          empty: t("#{scope}.empty"),
          intentId: t("#{scope}.intent_id"),
          userId: t("#{scope}.user_id"),
          purpose: t("#{scope}.purpose"),
          status: t("#{scope}.status"),
          attempts: t("#{scope}.attempts"),
          requestedAt: t("#{scope}.requested_at"),
          lastEventAt: t("#{scope}.last_event_at"),
          reason: t("#{scope}.reason"),
          retry: t("#{scope}.retry"),
          retryable: t("#{scope}.retryable"),
          terminal: t("#{scope}.terminal"),
          purposes: {
            password_reset: t("#{scope}.purposes.password_reset"),
            totp_recovery: t("#{scope}.purposes.totp_recovery")
          },
          statuses: {
            pending: t("#{scope}.statuses.pending"),
            sent: t("#{scope}.statuses.sent"),
            failed: t("#{scope}.statuses.failed")
          }
        }
      end

      def redis_recovery_copy
        scope = "mcweb.admin.redis_queue_recovery"
        {
          title: t("#{scope}.title"),
          description: t("#{scope}.description"),
          redis: t("#{scope}.redis"),
          ledger: t("#{scope}.ledger"),
          pending: t("#{scope}.pending"),
          retrying: t("#{scope}.retrying"),
          deadLettered: t("#{scope}.dead_lettered"),
          oldestPending: t("#{scope}.oldest_pending"),
          lastEnqueueFailure: t("#{scope}.last_enqueue_failure"),
          lastRecoveryHandoff: t("#{scope}.last_recovery_handoff"),
          lastRecoveryFailure: t("#{scope}.last_recovery_failure"),
          recoveryResult: t("#{scope}.recovery_result"),
          fallbackActive: t("#{scope}.fallback_active"),
          handoffNote: t("#{scope}.handoff_note"),
          statuses: {
            healthy: t("#{scope}.statuses.healthy"),
            recovering: t("#{scope}.statuses.recovering"),
            warning: t("#{scope}.statuses.warning"),
            unavailable: t("#{scope}.statuses.unavailable"),
            error: t("#{scope}.statuses.error"),
            local: t("#{scope}.statuses.local")
          },
          availability: {
            available: t("#{scope}.availability.available"),
            unavailable: t("#{scope}.availability.unavailable"),
            notApplicable: t("#{scope}.availability.not_applicable")
          },
          results: {
            accepted: t("#{scope}.results.accepted"),
            failed: t("#{scope}.results.failed"),
            none: t("#{scope}.results.none")
          },
          triggers: {
            maintenance: t("#{scope}.triggers.maintenance"),
            manual: t("#{scope}.triggers.manual")
          }
        }
      end

      def safe_manual_task_result(run)
        payload = run.result.is_a?(Hash) ? run.result.stringify_keys : {}
        error_codes = payload["error_codes"]
        error_codes_count = case error_codes
        when Array, Hash
          error_codes.size
        when String
          error_codes.present? ? 1 : 0
        else
          0
        end

        {
          partial: payload["partial"] == true,
          processed_count: nonnegative_result_count(
            payload["processed_count"] || payload["enqueued_count"]
          ),
          failed_count: nonnegative_result_count(payload["failed_count"]),
          error_codes_count:
        }
      end

      def nonnegative_result_count(value)
        count = Integer(value, exception: false)
        count && count >= 0 ? count : 0
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

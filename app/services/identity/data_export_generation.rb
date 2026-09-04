# frozen_string_literal: true

module Identity
  module DataExportGeneration
    HANDLER_KEY = "identity.data_export_generation"

    module_function

    def register(registry)
      registry.register(
        key: HANDLER_KEY,
        source_kind: "identity.data_export",
        queue: "default",
        replay_contract: "idempotent",
        lease: 1.hour,
        heartbeat: 1.minute,
        max_attempts: 5,
        retry_delays: [ 1.minute, 5.minutes, 30.minutes, 2.hours ]
      ) do |intent, _context|
        execute(intent)
      end
    end

    def record!(data_export:)
      Operations::DurableEnqueueAdmission.record!(
        handler: HANDLER_KEY,
        source_id: data_export.id,
        dedupe_key: dedupe_key_for(data_export)
      )
    end

    def execute(intent)
      data_export = Identity::DataExport.find_by(id: intent.source_id)
      return skipped("source_missing") unless data_export
      unless ActiveSupport::SecurityUtils.secure_compare(
        intent.dedupe_key,
        dedupe_key_for(data_export)
      )
        return skipped("data_export_request_superseded")
      end
      unless data_export.queued? || data_export.running?
        return skipped("data_export_not_queued")
      end

      Identity::BuildDataExportJob.perform_now(data_export.id, request_revision(data_export))
      data_export.reload
      unless ActiveSupport::SecurityUtils.secure_compare(
        intent.dedupe_key,
        dedupe_key_for(data_export)
      )
        return skipped("data_export_request_superseded")
      end

      return Operations::DurableEnqueueResult.succeeded if data_export.completed?
      if data_export.failed? || data_export.revoked? || data_export.expired?
        return skipped(normalize_error_code(data_export.error_code, fallback: "data_export_not_completed"))
      end

      raise Operations::DurableEnqueueCatalog::ExecutionError,
        "data_export_generation_incomplete"
    end

    def dedupe_key_for(data_export)
      "identity-data-export:#{data_export.id}:#{request_revision(data_export)}"
    end

    def current_intent(data_export)
      Operations::DurableEnqueueIntent.find_by(
        handler_key: HANDLER_KEY,
        source_id: data_export.id,
        dedupe_key: dedupe_key_for(data_export)
      )
    end

    def retryable_state(data_export, now: Time.current)
      return if data_export.failed? && data_export.error_code == "data_export_size_exceeded"
      return "failed" if data_export.failed?
      return "expired" if data_export.expired?

      if data_export.running?
        return unless Identity::BuildDataExportJob.stale_running?(data_export, at: now)
        return if live_execution?(data_export, now:)

        return "stale_running"
      end

      return unless data_export.queued?

      intent = current_intent(data_export)
      return "missing_intent" unless intent

      state = Operations::DurableEnqueueLedger.state(intent)
      "terminal_intent" if state.terminal?
    end

    def live_execution?(data_export, now: Time.current)
      intent = current_intent(data_export)
      return false unless intent

      state = Operations::DurableEnqueueLedger.state(intent)
      state.active_attempt.present? &&
        state.active_lease_expires_at.present? &&
        state.active_lease_expires_at > now
    end

    def request_revision(data_export)
      data_export.requested_at.utc.strftime("%Y%m%d%H%M%S%6N")
    end

    def normalize_error_code(value, fallback:)
      code = value.to_s
      code.match?(/\A[a-z][a-z0-9_]*\z/) ? code.first(120) : fallback
    end
    private_class_method :normalize_error_code

    def skipped(code)
      Operations::DurableEnqueueResult.skipped(error_code: code)
    end
    private_class_method :skipped
  end
end

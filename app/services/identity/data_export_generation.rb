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
        dedupe_key: "identity-data-export:#{data_export.id}:#{request_revision(data_export)}"
      )
    end

    def execute(intent)
      data_export = Identity::DataExport.find_by(id: intent.source_id)
      return skipped("source_missing") unless data_export
      return skipped("data_export_not_queued") unless data_export.queued?

      Identity::BuildDataExportJob.perform_now(data_export.id)
      data_export.reload

      return Operations::DurableEnqueueResult.succeeded if data_export.completed?
      if data_export.failed? || data_export.revoked? || data_export.expired?
        return skipped(normalize_error_code(data_export.error_code, fallback: "data_export_not_completed"))
      end

      raise Operations::DurableEnqueueCatalog::ExecutionError,
        "data_export_generation_incomplete"
    end

    def request_revision(data_export)
      data_export.requested_at.utc.strftime("%Y%m%d%H%M%S%6N")
    end
    private_class_method :request_revision

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

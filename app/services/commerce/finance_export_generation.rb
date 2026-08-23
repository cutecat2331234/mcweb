# frozen_string_literal: true

module Commerce
  module FinanceExportGeneration
    HANDLER_KEY = "commerce.finance_export_generation"

    module_function

    def register(registry)
      registry.register(
        key: HANDLER_KEY,
        source_kind: "commerce.finance_export",
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

    def record!(finance_export:)
      Operations::DurableEnqueueAdmission.record!(
        handler: HANDLER_KEY,
        source_id: finance_export.id,
        dedupe_key: "commerce-finance-export:#{finance_export.public_id}"
      )
    end

    def execute(intent)
      finance_export = Commerce::FinanceExport.find_by(id: intent.source_id)
      return skipped("source_missing") unless finance_export
      return skipped("finance_export_not_queued") unless finance_export.queued?

      Commerce::BuildFinanceExportJob.perform_now(finance_export.id)
      finance_export.reload

      return Operations::DurableEnqueueResult.succeeded if finance_export.completed?
      if finance_export.failed? || finance_export.revoked? || finance_export.expired?
        return skipped(normalize_error_code(finance_export.error_code, fallback: "finance_export_not_completed"))
      end

      raise Operations::DurableEnqueueCatalog::ExecutionError,
        "finance_export_generation_incomplete"
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

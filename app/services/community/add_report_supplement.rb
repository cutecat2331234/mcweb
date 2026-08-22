# frozen_string_literal: true

module Community
  class AddReportSupplement < ApplicationService
    def initialize(report:, reporter:, body:, idempotency_key:, expected_version:)
      @report = report
      @reporter = reporter
      @body = body.to_s.strip
      @idempotency_key = ReportMutationKey.normalize(idempotency_key)
      @expected_version = Integer(expected_version, exception: false)
    end

    def call
      return failure("report_supplement_blank") if @body.blank?
      return failure("report_supplement_too_long") if @body.length > ReportSupplement::MAX_BODY_LENGTH
      return failure("report_idempotency_key_invalid") unless @idempotency_key
      return failure("report_version_required") unless @expected_version && @expected_version >= 0

      result = nil
      Report.transaction(requires_new: true) do
        report = owned_report_scope.lock.find_by(id: @report&.id)
        unless report
          result = failure("report_not_found")
          raise ActiveRecord::Rollback
        end

        digest = ReportMutationKey.digest(@idempotency_key)
        existing = report.supplements.find_by(idempotency_key_digest: digest)
        if existing
          result = existing.body == @body ?
            success(report:, supplement: existing, replayed: true) :
            failure("report_idempotency_key_reused")
          next
        end

        unless report.pending?
          result = failure("report_not_pending")
          raise ActiveRecord::Rollback
        end
        unless report.lock_version == @expected_version
          result = failure("report_version_conflict")
          raise ActiveRecord::Rollback
        end

        supplement = report.supplements.create!(
          reporter: @reporter,
          body: @body,
          idempotency_key_digest: digest
        )
        report.touch
        Administration::AuditLogger.call(
          actor: @reporter,
          action: "community.report_supplement_added",
          resource: report,
          request_id: @idempotency_key,
          metadata: {
            supplement_id: supplement.id,
            body_digest: Digest::SHA256.hexdigest(@body)
          }
        )
        result = success(report:, supplement:, replayed: false)
      end
      result || failure("report_mutation_failed")
    rescue ActiveRecord::StaleObjectError
      failure("report_version_conflict")
    rescue ActiveRecord::RecordInvalid
      failure("report_mutation_failed")
    end

    private

    def owned_report_scope
      return Report.none unless @reporter&.persisted?

      Report.where(reporter_id: @reporter.id)
    end

    def success(**value)
      ServiceResult.success(value)
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end

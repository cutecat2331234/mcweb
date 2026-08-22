# frozen_string_literal: true

module Community
  class WithdrawReport < ApplicationService
    DESIRED_STATE = "withdrawn"

    def initialize(report:, reporter:, desired_state:, idempotency_key:, expected_version:)
      @report = report
      @reporter = reporter
      @desired_state = desired_state.to_s
      @idempotency_key = ReportMutationKey.normalize(idempotency_key)
      @expected_version = Integer(expected_version, exception: false)
    end

    def call
      return failure("report_state_invalid") unless @desired_state == DESIRED_STATE
      return failure("report_idempotency_key_invalid") unless @idempotency_key
      return failure("report_version_required") unless @expected_version && @expected_version >= 0

      result = nil
      Report.transaction(requires_new: true) do
        candidate = owned_report_scope.find_by(id: @report&.id)
        unless candidate
          result = failure("report_not_found")
          raise ActiveRecord::Rollback
        end
        lock_hideable_target(candidate)
        report = owned_report_scope.lock.find_by(id: candidate.id)
        unless report
          result = failure("report_not_found")
          raise ActiveRecord::Rollback
        end
        if report.withdrawn?
          result = success(report:, replayed: true)
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

        digest = ReportMutationKey.digest(@idempotency_key)
        report.update!(
          status: DESIRED_STATE,
          dedupe_key: nil,
          withdrawal_idempotency_key_digest: digest,
          withdrawn_at: Time.current,
          state_changed_at: Time.current
        )
        Administration::AuditLogger.call(
          actor: @reporter,
          action: "community.report_withdrawn",
          resource: report,
          request_id: @idempotency_key,
          before_state: { status: "pending", lock_version: @expected_version },
          after_state: { status: report.status, lock_version: report.lock_version }
        )
        result = success(report:, replayed: false)
      end
      result || failure("report_mutation_failed")
    rescue ActiveRecord::StaleObjectError
      failure("report_version_conflict")
    rescue ActiveRecord::Deadlocked,
      Community::SectionHierarchyLock::HierarchyChanged,
      Community::SectionHierarchyLock::TopicSectionChanged,
      Community::ReportTargetLock::PostTopicChanged
      failure("report_version_conflict")
    rescue ActiveRecord::RecordInvalid
      failure("report_mutation_failed")
    end

    private

    def owned_report_scope
      return Report.none unless @reporter&.persisted?

      Report.where(reporter_id: @reporter.id)
    end

    def lock_hideable_target(report)
      reportable = report.reportable
      return unless Community::ReportTargetLock.hideable?(reportable)

      Community::ReportTargetLock.lock!(reportable)
    end

    def success(**value)
      ServiceResult.success(value)
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end

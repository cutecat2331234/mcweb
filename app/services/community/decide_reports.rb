# frozen_string_literal: true

module Community
  class DecideReports < ApplicationService
    class DecisionFailure < StandardError
      attr_reader :result

      def initialize(result)
        @result = result
        super(result.code || result.error)
      end
    end

    def initialize(scope:, reportable:, reviewer:, desired_status:, idempotency_key:, internal_note: nil)
      @scope = scope
      @reportable = reportable
      @reviewer = reviewer
      @desired_status = desired_status.to_s
      @idempotency_key = ReportMutationKey.normalize(idempotency_key)
      @internal_note = internal_note.to_s.strip.presence
    end

    def call
      validation = validation_failure
      return validation if validation

      @idempotency_key_digest = ReportMutationKey.digest(@idempotency_key)
      @request_fingerprint = request_fingerprint
      result = nil
      Report.transaction(requires_new: true) do
        lock_idempotency_key!
        existing = ReportDecisionBatch.find_by(idempotency_key_digest: @idempotency_key_digest)
        if existing
          result = replay_result(existing)
          next
        end

        locked_reportable = lock_reportable_for_decision
        reports = @scope
          .pending_review
          .where(reportable: locked_reportable)
          .order(:id)
          .lock
          .to_a
        decided = reports.map { |report| decide!(report) }
        batch = ReportDecisionBatch.create!(
          idempotency_key_digest: @idempotency_key_digest,
          request_fingerprint: @request_fingerprint,
          reviewer: @reviewer,
          reportable_type: @reportable.class.polymorphic_name,
          reportable_id: @reportable.id,
          desired_status: @desired_status,
          report_ids: decided.map(&:id),
          decided_count: decided.size
        )
        result = success(decided, batch:, replayed: false)
      end
      result || failure("report_mutation_failed")
    rescue DecisionFailure => error
      error.result
    rescue ActiveRecord::RecordNotFound
      failure("report_target_unavailable")
    rescue ActiveRecord::RecordNotUnique
      existing = ReportDecisionBatch.find_by(idempotency_key_digest: @idempotency_key_digest)
      existing ? replay_result(existing) : failure("report_mutation_failed")
    rescue ActiveRecord::RecordInvalid
      failure("report_mutation_failed")
    rescue ActiveRecord::Deadlocked,
      Community::SectionHierarchyLock::HierarchyChanged,
      Community::SectionHierarchyLock::TopicSectionChanged,
      Community::ReportTargetLock::PostTopicChanged
      failure("report_version_conflict")
    end

    private

    def validation_failure
      return failure("report_state_invalid") unless Report::STAFF_FINAL_STATUSES.include?(@desired_status)
      return failure("report_reviewer_required") unless @reviewer&.persisted?
      return failure("report_idempotency_key_invalid") unless @idempotency_key
      if @internal_note&.length.to_i > DecideReport::MAX_INTERNAL_NOTE_LENGTH
        return failure("report_internal_note_too_long")
      end
      return failure("report_target_unavailable") unless @reportable&.persisted?

      nil
    end

    def lock_reportable_for_decision
      return @reportable unless Community::ReportTargetLock.hideable?(@reportable)

      Community::ReportTargetLock.lock!(@reportable) || raise(ActiveRecord::RecordNotFound)
    end

    def decide!(report)
      result = DecideReport.call(
        report:,
        reviewer: @reviewer,
        desired_status: @desired_status,
        idempotency_key: @idempotency_key,
        internal_note: @internal_note,
        require_expected_version: false
      )
      raise DecisionFailure.new(result) if result.failure?

      result.value.fetch(:report)
    end

    def replay_result(batch)
      return failure("report_idempotency_key_reused") unless matching_batch?(batch)

      reports_by_id = Report.where(id: batch.report_ids).index_by(&:id)
      reports = batch.report_ids.filter_map { |id| reports_by_id[id] }
      success(reports, batch:, replayed: true)
    end

    def matching_batch?(batch)
      batch.reviewer_id == @reviewer.id &&
        batch.reportable_type == @reportable.class.polymorphic_name &&
        batch.reportable_id == @reportable.id &&
        batch.desired_status == @desired_status &&
        secure_match?(batch.request_fingerprint, @request_fingerprint)
    end

    def success(reports, batch:, replayed:)
      ServiceResult.success(
        reports:,
        count: batch.decided_count,
        batch:,
        replayed:
      )
    end

    def request_fingerprint
      Digest::SHA256.hexdigest(
        ActiveSupport::JSON.encode(
          {
            reviewer_id: @reviewer.id,
            reportable_type: @reportable.class.polymorphic_name,
            reportable_id: @reportable.id,
            desired_status: @desired_status,
            internal_note: @internal_note
          }
        )
      )
    end

    def lock_idempotency_key!
      lock_id = @idempotency_key_digest.first(16).to_i(16)
      lock_id -= 2**64 if lock_id >= 2**63
      sql = ActiveRecord::Base.sanitize_sql_array(
        [ "SELECT pg_advisory_xact_lock(?)", lock_id ]
      )
      Report.connection.select_value(sql)
    end

    def secure_match?(left, right)
      left = left.to_s
      right = right.to_s
      left.bytesize == right.bytesize && ActiveSupport::SecurityUtils.secure_compare(left, right)
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end

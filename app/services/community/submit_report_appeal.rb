# frozen_string_literal: true

module Community
  class SubmitReportAppeal < ApplicationService
    def initialize(appeal:, appellant:, reason:, attachment_public_ids:, idempotency_key:,
                   expected_version:, now: Time.current)
      @appeal = appeal
      @appellant = appellant
      @reason = reason.to_s.strip
      @attachment_public_ids = Array(attachment_public_ids)
      @idempotency_key = ReportMutationKey.normalize(idempotency_key)
      @expected_version = Integer(expected_version, exception: false)
      @now = now
    end

    def call
      validation = validation_failure
      return validation if validation

      digest = ReportMutationKey.digest(@idempotency_key)
      normalized_attachment_ids = @attachment_public_ids.map { |value| value.to_s.strip }.reject(&:blank?).uniq.sort
      fingerprint = ReportAppealMutation.fingerprint(
        appeal_public_id: @appeal.public_id,
        appellant_id: @appellant.id,
        reason: @reason,
        attachment_public_ids: normalized_attachment_ids
      )
      result = nil

      ReportAppeal.transaction(requires_new: true) do
        report = Report.lock.find_by(id: @appeal.forum_report_id)
        appeal = ReportAppeal.lock.find_by(id: @appeal.id)
        unless report && appeal && appeal.appellant_id == @appellant.id
          result = failure("report_appeal_unavailable")
          raise ActiveRecord::Rollback
        end
        lock_users(report, appeal)

        if appeal.submit_idempotency_key_digest
          result = replay_result(appeal, digest, fingerprint)
          next
        end
        unless appeal.draft?
          result = failure("report_appeal_state_conflict")
          raise ActiveRecord::Rollback
        end
        if appeal.draft_expired?(@now)
          result = failure("report_appeal_draft_expired")
          raise ActiveRecord::Rollback
        end
        if appeal.lock_version != @expected_version
          result = failure("report_appeal_version_conflict")
          raise ActiveRecord::Rollback
        end
        unless ReportAppealPolicy.new(@appellant).may_create?(report:, role: appeal.appellant_role)
          result = failure("report_appeal_unavailable")
          raise ActiveRecord::Rollback
        end

        attachments = ReportEvidenceBinder.lock_clean!(
          subject_key: "community.report_appeal",
          subject: appeal,
          actor: @appellant,
          public_ids: normalized_attachment_ids
        )
        appeal.update!(
          reason: @reason,
          status: "submitted",
          state_changed_at: @now,
          expires_at: nil,
          submitted_at: @now,
          submit_idempotency_key_digest: digest,
          submit_request_fingerprint: fingerprint
        )
        attachments.each do |attachment|
          ReportAppealAttachment.create!(
            appeal:,
            attachment:,
            sealed_by: @appellant,
            audience: "appellant",
            created_at: @now
          )
        end
        ReportAppealMutation.record_event!(
          appeal:,
          actor: @appellant,
          event_type: "submitted",
          from_status: "draft",
          to_status: "submitted",
          idempotency_key_digest: digest,
          request_fingerprint: fingerprint,
          occurred_at: @now
        )
        Administration::AuditLogger.call(
          actor: @appellant,
          action: "community.report_appeal_submitted",
          resource: appeal,
          request_id: @idempotency_key,
          metadata: {
            appellant_role: appeal.appellant_role,
            attachment_count: attachments.size,
            report_public_id: report.public_id
          }
        )
        result = success(appeal, replayed: false)
      end

      publish_submitted(result)
      result || failure("report_appeal_mutation_failed")
    rescue ReportEvidenceBinder::BindingError => error
      failure(error.code)
    rescue ActiveRecord::StaleObjectError
      failure("report_appeal_version_conflict")
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ActiveRecord::Deadlocked
      failure("report_appeal_mutation_failed")
    end

    private

    def validation_failure
      return failure("report_appeal_unavailable") unless @appeal&.persisted? && @appellant&.persisted?
      return failure("report_appeal_reason_required") if @reason.blank?
      return failure("report_appeal_reason_too_long") if @reason.length > ReportAppeal::MAX_REASON_LENGTH
      return failure("report_appeal_idempotency_key_invalid") unless @idempotency_key
      return failure("report_appeal_version_required") unless @expected_version && @expected_version >= 0
      if @attachment_public_ids.map(&:to_s).reject(&:blank?).uniq.size > ReportEvidenceBinder::MAX_ATTACHMENTS
        return failure("report_evidence_limit_exceeded")
      end

      nil
    end

    def lock_users(report, appeal)
      User.where(id: [ report.reporter_id, report.affected_user_id, appeal.appellant_id ].compact.uniq)
        .order(:id)
        .lock
        .load
    end

    def replay_result(appeal, digest, fingerprint)
      matches = ReportAppealMutation.secure_match?(appeal.submit_idempotency_key_digest, digest) &&
        ReportAppealMutation.secure_match?(appeal.submit_request_fingerprint, fingerprint)
      matches ? success(appeal, replayed: true) : failure("report_appeal_idempotency_conflict")
    end

    def publish_submitted(result)
      return unless result&.success? && !result.value.fetch(:replayed)

      Mcweb::Events.publish(
        "forum.report_appeal.submitted",
        appeal: result.value.fetch(:appeal),
        appellant: @appellant
      )
    end

    def success(appeal, replayed:)
      ServiceResult.success(appeal:, replayed:)
    end

    def failure(code)
      ReportAppealMutation.failure(code)
    end
  end
end

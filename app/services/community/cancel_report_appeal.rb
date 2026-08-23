# frozen_string_literal: true

module Community
  class CancelReportAppeal < ApplicationService
    def initialize(appeal:, appellant:, idempotency_key:, expected_version:, now: Time.current)
      @appeal = appeal
      @appellant = appellant
      @idempotency_key = ReportMutationKey.normalize(idempotency_key)
      @expected_version = Integer(expected_version, exception: false)
      @now = now
    end

    def call
      return failure("report_appeal_unavailable") unless @appeal&.persisted? && @appellant&.persisted?
      return failure("report_appeal_idempotency_key_invalid") unless @idempotency_key
      return failure("report_appeal_version_required") unless @expected_version&.nonnegative?

      digest = ReportMutationKey.digest(@idempotency_key)
      fingerprint = ReportAppealMutation.fingerprint(
        appeal_public_id: @appeal.public_id,
        appellant_id: @appellant.id,
        desired_status: "cancelled"
      )
      result = nil
      discard_draft = false

      ReportAppeal.transaction(requires_new: true) do
        report = Report.lock.find_by(id: @appeal.forum_report_id)
        appeal = ReportAppeal.lock.find_by(id: @appeal.id)
        unless report && appeal && appeal.appellant_id == @appellant.id
          result = failure("report_appeal_unavailable")
          raise ActiveRecord::Rollback
        end
        lock_users(report, appeal)

        if appeal.cancelled?
          result = replay_result(appeal, digest, fingerprint)
          next
        end
        unless appeal.draft? || appeal.submitted?
          result = failure("report_appeal_state_conflict")
          raise ActiveRecord::Rollback
        end
        if appeal.lock_version != @expected_version
          result = failure("report_appeal_version_conflict")
          raise ActiveRecord::Rollback
        end

        from_status = appeal.status
        discard_draft = appeal.draft?
        appeal.update!(
          status: "cancelled",
          public_outcome_code: "cancelled",
          state_changed_at: @now,
          expires_at: nil,
          cancelled_at: @now,
          cancel_idempotency_key_digest: digest,
          cancel_request_fingerprint: fingerprint
        )
        ReportAppealMutation.record_event!(
          appeal:,
          actor: @appellant,
          event_type: "cancelled",
          from_status:,
          to_status: "cancelled",
          public_outcome_code: "cancelled",
          idempotency_key_digest: digest,
          request_fingerprint: fingerprint,
          occurred_at: @now
        )
        Administration::AuditLogger.call(
          actor: @appellant,
          action: "community.report_appeal_cancelled",
          resource: appeal,
          request_id: @idempotency_key,
          before_state: { status: from_status },
          after_state: { status: "cancelled" }
        )
        result = success(appeal, replayed: false)
      end

      discard_draft_attachments if result&.success? && discard_draft
      publish_cancelled(result)
      result || failure("report_appeal_mutation_failed")
    rescue ActiveRecord::StaleObjectError
      failure("report_appeal_version_conflict")
    rescue ActiveRecord::RecordInvalid, ActiveRecord::Deadlocked
      failure("report_appeal_mutation_failed")
    end

    private

    def lock_users(report, appeal)
      User.where(id: [ report.reporter_id, report.affected_user_id, appeal.appellant_id ].compact.uniq)
        .order(:id)
        .lock
        .load
    end

    def replay_result(appeal, digest, fingerprint)
      matches = ReportAppealMutation.secure_match?(appeal.cancel_idempotency_key_digest, digest) &&
        ReportAppealMutation.secure_match?(appeal.cancel_request_fingerprint, fingerprint)
      matches ? success(appeal, replayed: true) : failure("report_appeal_idempotency_conflict")
    end

    def discard_draft_attachments
      SecureEvidence::Attachment.where(
        subject_key: "community.report_appeal",
        subject_id: @appeal.id,
        subject_public_id: @appeal.public_id,
        uploader_id: @appellant.id
      ).find_each do |attachment|
        SecureEvidence::DiscardAttachment.call(attachment:, actor: @appellant)
      end
    end

    def publish_cancelled(result)
      return unless result&.success? && !result.value.fetch(:replayed)

      Mcweb::Events.publish(
        "forum.report_appeal.cancelled",
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

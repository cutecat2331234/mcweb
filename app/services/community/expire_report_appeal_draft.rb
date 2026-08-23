# frozen_string_literal: true

module Community
  class ExpireReportAppealDraft < ApplicationService
    def initialize(appeal:, now: Time.current)
      @appeal = appeal
      @now = now
    end

    def call
      return failure("report_appeal_unavailable") unless @appeal&.persisted?

      result = nil
      appellant = nil
      ReportAppeal.transaction(requires_new: true) do
        report = Report.lock.find_by(id: @appeal.forum_report_id)
        appeal = ReportAppeal.lock.find_by(id: @appeal.id)
        unless report && appeal
          result = failure("report_appeal_unavailable")
          raise ActiveRecord::Rollback
        end
        appellant = appeal.appellant
        unless appeal.draft?
          result = ServiceResult.success(appeal:, replayed: true)
          next
        end
        unless appeal.draft_expired?(@now)
          result = failure("report_appeal_draft_not_expired")
          raise ActiveRecord::Rollback
        end

        digest = Digest::SHA256.hexdigest("report-appeal-expire:#{appeal.public_id}")
        fingerprint = ReportAppealMutation.fingerprint(
          appeal_public_id: appeal.public_id,
          desired_status: "cancelled",
          reason: "expired"
        )
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
          actor: nil,
          event_type: "cancelled",
          from_status: "draft",
          to_status: "cancelled",
          public_outcome_code: "cancelled",
          idempotency_key_digest: digest,
          request_fingerprint: fingerprint,
          occurred_at: @now
        )
        Administration::AuditLogger.call(
          actor: nil,
          action: "community.report_appeal_draft_expired",
          resource: appeal,
          metadata: { appellant_role: appeal.appellant_role }
        )
        result = ServiceResult.success(appeal:, replayed: false)
      end

      discard_attachments(result.value.fetch(:appeal), appellant) if result&.success? && !result.value.fetch(:replayed)
      result || failure("report_appeal_mutation_failed")
    rescue ActiveRecord::RecordInvalid, ActiveRecord::Deadlocked
      failure("report_appeal_mutation_failed")
    end

    private

    def discard_attachments(appeal, appellant)
      SecureEvidence::Attachment.where(
        subject_key: "community.report_appeal",
        subject_id: appeal.id,
        subject_public_id: appeal.public_id,
        uploader_id: appellant.id
      ).find_each do |attachment|
        SecureEvidence::DiscardAttachment.call(attachment:, actor: appellant)
      end
    end

    def failure(code)
      ReportAppealMutation.failure(code)
    end
  end
end

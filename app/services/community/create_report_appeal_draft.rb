# frozen_string_literal: true

module Community
  class CreateReportAppealDraft < ApplicationService
    def initialize(report:, appellant:, appellant_role:, idempotency_key:, now: Time.current)
      @report = report
      @appellant = appellant
      @appellant_role = appellant_role.to_s
      @idempotency_key = ReportMutationKey.normalize(idempotency_key)
      @now = now
    end

    def call
      return failure("report_appeal_unavailable") unless @report&.persisted? && @appellant&.persisted?
      return failure("report_appeal_role_invalid") unless ReportAppeal::APPELLANT_ROLES.include?(@appellant_role)
      return failure("report_appeal_idempotency_key_invalid") unless @idempotency_key

      digest = ReportMutationKey.digest(@idempotency_key)
      fingerprint = ReportAppealMutation.fingerprint(
        report_public_id: @report.public_id,
        appellant_id: @appellant.id,
        appellant_role: @appellant_role
      )
      result = nil
      expired = nil

      ReportAppeal.transaction(requires_new: true) do
        report = Report.lock.find_by(id: @report.id)
        unless report
          result = failure("report_appeal_unavailable")
          raise ActiveRecord::Rollback
        end
        lock_users(report)

        existing_by_key = ReportAppeal.find_by(
          appellant_id: @appellant.id,
          draft_idempotency_key_digest: digest
        )
        if existing_by_key
          result = replay_result(existing_by_key, fingerprint)
          next
        end

        unless ReportAppealPolicy.new(@appellant).may_create?(report:, role: @appellant_role)
          result = failure("report_appeal_unavailable")
          raise ActiveRecord::Rollback
        end

        active = ReportAppeal.active.lock.find_by(
          report:,
          appellant: @appellant,
          appellant_role: @appellant_role
        )
        if active&.draft_expired?(@now)
          expire_locked_draft!(active)
          expired = active
          active = nil
        end
        if active
          result = active.draft? ? success(active, replayed: true) : failure("report_appeal_already_active")
          next
        end

        appeal = ReportAppeal.create!(
          report:,
          appellant: @appellant,
          appellant_role: @appellant_role,
          status: "draft",
          state_changed_at: @now,
          expires_at: @now + ReportAppeal::DRAFT_TTL,
          draft_idempotency_key_digest: digest,
          draft_request_fingerprint: fingerprint
        )
        ReportAppealMutation.record_event!(
          appeal:,
          actor: @appellant,
          event_type: "drafted",
          from_status: nil,
          to_status: "draft",
          idempotency_key_digest: digest,
          request_fingerprint: fingerprint,
          occurred_at: @now
        )
        Administration::AuditLogger.call(
          actor: @appellant,
          action: "community.report_appeal_drafted",
          resource: appeal,
          request_id: @idempotency_key,
          metadata: { appellant_role: @appellant_role, report_public_id: report.public_id }
        )
        result = success(appeal, replayed: false)
      end

      discard_unsealed_draft_attachments(expired) if expired
      result || failure("report_appeal_mutation_failed")
    rescue ActiveRecord::RecordNotUnique
      existing_by_key = ReportAppeal.find_by(
        appellant_id: @appellant.id,
        draft_idempotency_key_digest: digest
      )
      return replay_result(existing_by_key, fingerprint) if existing_by_key

      active = ReportAppeal.active.find_by(
        forum_report_id: @report.id,
        appellant_id: @appellant.id,
        appellant_role: @appellant_role
      )
      active ? failure("report_appeal_already_active") : failure("report_appeal_mutation_failed")
    rescue ActiveRecord::RecordInvalid
      failure("report_appeal_mutation_failed")
    end

    private

    def lock_users(report)
      User.where(id: [ report.reporter_id, report.affected_user_id, @appellant.id ].compact.uniq)
        .order(:id)
        .lock
        .load
    end

    def expire_locked_draft!(appeal)
      digest = Digest::SHA256.hexdigest("report-appeal-expire:#{appeal.public_id}")
      fingerprint = ReportAppealMutation.fingerprint(appeal_public_id: appeal.public_id, status: "cancelled")
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
    end

    def discard_unsealed_draft_attachments(appeal)
      return unless appeal

      SecureEvidence::Attachment.where(
        subject_key: "community.report_appeal",
        subject_id: appeal.id,
        subject_public_id: appeal.public_id,
        uploader_id: appeal.appellant_id
      ).find_each do |attachment|
        SecureEvidence::DiscardAttachment.call(attachment:, actor: appeal.appellant)
      end
    end

    def replay_result(appeal, fingerprint)
      return failure("report_appeal_idempotency_conflict") unless ReportAppealMutation.secure_match?(
        appeal.draft_request_fingerprint,
        fingerprint
      )

      success(appeal, replayed: true)
    end

    def success(appeal, replayed:)
      ServiceResult.success(appeal:, replayed:)
    end

    def failure(code)
      ReportAppealMutation.failure(code)
    end
  end
end

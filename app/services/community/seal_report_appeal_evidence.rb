# frozen_string_literal: true

module Community
  class SealReportAppealEvidence < ApplicationService
    def initialize(appeal:, reviewer:, attachment_public_ids:, now: Time.current)
      @appeal = appeal
      @reviewer = reviewer
      @attachment_public_ids = attachment_public_ids
      @now = now
    end

    def call
      return failure("report_evidence_unavailable") unless @appeal&.persisted? && @reviewer&.persisted?
      public_ids = normalize_public_ids
      return failure("report_evidence_unavailable") if public_ids.empty?
      if public_ids.size > ReportEvidenceBinder::MAX_ATTACHMENTS
        return failure("report_evidence_limit_exceeded")
      end

      links = nil
      replayed = false
      ReportAppeal.transaction(requires_new: true) do
        report = Report.lock.find_by(id: @appeal.forum_report_id)
        appeal = ReportAppeal.lock.find_by(id: @appeal.id)
        policy = ReportAppealPolicy.new(@reviewer)
        unless report && appeal && (appeal.submitted? || appeal.under_review?) && policy.reviewer_visible?(appeal)
          raise ReportEvidenceBinder::BindingError, "report_evidence_unavailable"
        end

        User.where(id: [ report.reporter_id, report.affected_user_id, appeal.appellant_id, @reviewer.id ].compact.uniq)
          .order(:id)
          .lock
          .load
        existing_links = ReportAppealAttachment.joins(:attachment)
          .where(appeal:, secure_evidence_attachments: { public_id: public_ids })
          .includes(:attachment)
          .order(:id)
          .to_a
        if existing_links.any? { |link| link.sealed_by_id != @reviewer.id }
          raise ReportEvidenceBinder::BindingError, "report_evidence_already_sealed"
        end
        existing_public_ids = existing_links.map { |link| link.attachment.public_id }
        remaining_public_ids = public_ids - existing_public_ids
        attachments = ReportEvidenceBinder.lock_clean!(
          subject_key: "community.report_appeal",
          subject: appeal,
          actor: @reviewer,
          public_ids: remaining_public_ids
        )
        current_count = ReportAppealAttachment.where(appeal:).count
        if current_count + attachments.size > ReportEvidenceBinder::MAX_ATTACHMENTS
          raise ReportEvidenceBinder::BindingError, "report_evidence_limit_exceeded"
        end

        created_links = attachments.map do |attachment|
          ReportAppealAttachment.create!(
            appeal:,
            attachment:,
            sealed_by: @reviewer,
            audience: "reviewers",
            created_at: @now
          )
        end
        links = existing_links + created_links
        replayed = created_links.empty?
        if created_links.any?
          Administration::AuditLogger.call(
            actor: @reviewer,
            action: "community.report_appeal_reviewer_evidence_sealed",
            resource: appeal,
            metadata: {
              attachment_public_ids: attachments.map(&:public_id),
              attachment_count: attachments.size,
              report_public_id: report.public_id
            }
          )
        end
      end
      ServiceResult.success(links: links || [], replayed:)
    rescue ReportEvidenceBinder::BindingError => error
      failure(error.code)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ActiveRecord::Deadlocked
      failure("report_evidence_mutation_failed")
    end

    private

    def normalize_public_ids
      Array(@attachment_public_ids).map { |value| value.to_s.strip }.reject(&:blank?).uniq.sort
    end

    def failure(code)
      ServiceResult.failure(error: code, code:)
    end
  end
end

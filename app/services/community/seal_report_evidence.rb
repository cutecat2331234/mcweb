# frozen_string_literal: true

module Community
  class SealReportEvidence < ApplicationService
    def initialize(report:, actor:, attachment_public_ids:)
      @report = report
      @actor = actor
      @attachment_public_ids = attachment_public_ids
    end

    def call
      return failure("report_evidence_unavailable") unless @report&.persisted? && @actor&.persisted?
      public_ids = normalize_public_ids
      return failure("report_evidence_unavailable") if public_ids.empty?
      if public_ids.size > ReportEvidenceBinder::MAX_ATTACHMENTS
        return failure("report_evidence_limit_exceeded")
      end

      links = nil
      replayed = false
      Report.transaction(requires_new: true) do
        report = Report.lock.find_by(id: @report.id)
        unless report&.pending? && report.reporter_id == @actor.id
          raise ReportEvidenceBinder::BindingError, "report_evidence_unavailable"
        end

        existing_links = ReportAttachment.joins(:attachment)
          .where(report:, secure_evidence_attachments: { public_id: public_ids })
          .includes(:attachment)
          .order(:id)
          .to_a
        if existing_links.any? { |link| link.sealed_by_id != @actor.id }
          raise ReportEvidenceBinder::BindingError, "report_evidence_already_sealed"
        end
        existing_public_ids = existing_links.map { |link| link.attachment.public_id }
        remaining_public_ids = public_ids - existing_public_ids
        attachments = ReportEvidenceBinder.lock_clean!(
          subject_key: "community.report",
          subject: report,
          actor: @actor,
          public_ids: remaining_public_ids
        )
        current_count = ReportAttachment.where(report:).count
        if current_count + attachments.size > ReportEvidenceBinder::MAX_ATTACHMENTS
          raise ReportEvidenceBinder::BindingError, "report_evidence_limit_exceeded"
        end
        created_links = attachments.map do |attachment|
          ReportAttachment.create!(report:, attachment:, sealed_by: @actor, created_at: Time.current)
        end
        links = existing_links + created_links
        replayed = created_links.empty?
        if created_links.any?
          Administration::AuditLogger.call(
            actor: @actor,
            action: "community.report_evidence_sealed",
            resource: report,
            metadata: {
              attachment_public_ids: attachments.map(&:public_id),
              attachment_count: attachments.size
            }
          )
        end
      end
      ServiceResult.success(links: links || [], replayed:)
    rescue ReportEvidenceBinder::BindingError => error
      failure(error.code)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
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

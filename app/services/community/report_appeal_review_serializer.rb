# frozen_string_literal: true

module Community
  class ReportAppealReviewSerializer
    def initialize(appeal:, decision_url:, viewer:, detail_url: decision_url, evidence_url: nil,
                   routes: Rails.application.routes.url_helpers)
      @appeal = appeal
      @decision_url = decision_url
      @detail_url = detail_url
      @evidence_url = evidence_url
      @viewer = viewer
      @routes = routes
    end

    def summary
      {
        public_id: @appeal.public_id,
        appellant_role: @appeal.appellant_role,
        appellant: @appeal.appellant.username,
        status: @appeal.status,
        submitted_at: localized(@appeal.submitted_at),
        state_changed_at: localized(@appeal.state_changed_at),
        report_target: safe_target_label,
        detail_url: @detail_url
      }
    end

    def detail
      summary.merge(
        lock_version: @appeal.lock_version,
        decision_url: @decision_url,
        evidence_url: @evidence_url,
        evidence_upload_url: @routes.secure_evidence_attachments_path,
        evidence_subject: { key: "community.report_appeal", public_id: @appeal.public_id },
        can_add_evidence: (@appeal.submitted? || @appeal.under_review?) && @evidence_url.present?,
        can_decide: @appeal.submitted? || @appeal.under_review?,
        public_case: {
          reason: @appeal.reason,
          public_outcome_code: @appeal.public_outcome_code,
          events: @appeal.events.timeline.map do |event|
            {
              type: event.event_type,
              from_status: event.from_status,
              to_status: event.to_status,
              public_outcome_code: event.public_outcome_code,
              occurred_at: localized(event.occurred_at)
            }
          end
        },
        internal_case: {
          report_public_id: @appeal.report.public_id,
          report_status: @appeal.report.status,
          report_reason_label: @appeal.report.reason_label,
          report_reason_detail: report_reason_detail,
          reporter: @appeal.report.reporter.username,
          affected_user: @appeal.report.affected_user&.username,
          reviewer: @appeal.reviewer&.username,
          internal_note: @appeal.internal_note
        },
        attachments: attachments
      )
    end

    private

    def attachments
      sealed_links = @appeal.evidence_links.includes(attachment: :upload_record).order(:created_at, :id)
      sealed_ids = sealed_links.map(&:secure_evidence_attachment_id)
      pending = SecureEvidence::Attachment
        .where(
          subject_key: "community.report_appeal",
          subject_id: @appeal.id,
          subject_public_id: @appeal.public_id,
          uploader_id: @viewer.id
        )
        .where.not(id: sealed_ids)
        .where.not(state: "purged")
        .includes(:upload_record)
        .order(:created_at, :id)

      sealed_links.map do |link|
        attachment_payload(link.attachment, sealed: true, audience: link.audience)
      end + pending.map do |attachment|
        attachment_payload(attachment, sealed: false, audience: "reviewers")
      end
    end

    def attachment_payload(attachment, sealed:, audience:)
      payload = {
        public_id: attachment.public_id,
        filename: attachment.filename,
        byte_size: attachment.byte_size,
        sha256: attachment.sha256,
        state: attachment.state,
        scan_status: attachment.upload_record&.scan_status,
        scan_status_url: @routes.scan_status_secure_evidence_attachment_path(attachment),
        download_url: @routes.secure_evidence_attachment_path(attachment),
        sealed:,
        audience:
      }
      if !sealed && SecureEvidence::AttachmentAccess.discard_allowed?(attachment, actor: @viewer)
        payload[:discard_url] = @routes.secure_evidence_attachment_path(attachment)
      end
      payload
    end

    def safe_target_label
      Community::ReporterReportSerializer.new(report: @appeal.report).safe_target_label
    end

    def report_reason_detail
      detail = @appeal.report.reason.to_s
      return if @appeal.report.reason_code.present? && detail == @appeal.report.reason_code

      detail.presence
    end

    def localized(value)
      I18n.l(value, format: :long) if value
    end
  end
end

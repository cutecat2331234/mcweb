# frozen_string_literal: true

module Community
  class ReportAppealSerializer
    def initialize(appeal:, viewer:, routes: Rails.application.routes.url_helpers)
      @appeal = appeal
      @viewer = viewer
      @routes = routes
    end

    def summary
      {
        id: @appeal.public_id,
        public_id: @appeal.public_id,
        appellant_role: @appeal.appellant_role,
        status: @appeal.status,
        public_outcome_code: @appeal.public_outcome_code,
        submitted_at: localized(@appeal.submitted_at),
        state_changed_at: localized(@appeal.state_changed_at),
        detail_url: @routes.forum_report_appeal_path(@appeal)
      }
    end

    def detail
      summary.merge(
        reason: @appeal.reason,
        lock_version: @appeal.lock_version,
        expires_at: localized(@appeal.expires_at),
        report: safe_report,
        index_url: @routes.forum_report_appeals_path,
        submit_url: @routes.submit_forum_report_appeal_path(@appeal),
        cancel_url: @routes.cancel_forum_report_appeal_path(@appeal),
        evidence_subject: {
          key: "community.report_appeal",
          public_id: @appeal.public_id
        },
        attachments: attachments,
        events: @appeal.events.timeline.map do |event|
          {
            type: event.event_type,
            from_status: event.from_status,
            to_status: event.to_status,
            public_outcome_code: event.public_outcome_code,
            occurred_at: localized(event.occurred_at)
          }
        end,
        can_submit: @appeal.draft? && !@appeal.draft_expired? && @appeal.appellant_id == @viewer.id,
        can_cancel: (@appeal.draft? || @appeal.submitted?) && @appeal.appellant_id == @viewer.id
      )
    end

    private

    def safe_report
      payload = {
        public_id: @appeal.report.public_id,
        target_label: ReporterReportSerializer.new(report: @appeal.report).safe_target_label
      }
      if @appeal.appellant_role_reporter?
        payload[:reason_label] = @appeal.report.reason_label
      end
      payload
    end

    def attachments
      sealed_links = @appeal.evidence_links
        .where(audience: "appellant")
        .includes(attachment: :upload_record)
        .order(:created_at, :id)
      sealed_ids = sealed_links.map(&:secure_evidence_attachment_id)
      unsealed = SecureEvidence::Attachment
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

      sealed_links.map { |link| attachment_payload(link.attachment, sealed: true) } +
        unsealed.map { |attachment| attachment_payload(attachment, sealed: false) }
    end

    def attachment_payload(attachment, sealed:)
      upload = attachment.upload_record
      result = {
        public_id: attachment.public_id,
        filename: attachment.filename,
        byte_size: attachment.byte_size,
        sha256: attachment.sha256,
        state: attachment.state,
        scan_status: upload&.scan_status,
        scan_status_url: @routes.scan_status_secure_evidence_attachment_path(attachment),
        download_url: @routes.secure_evidence_attachment_path(attachment),
        sealed:
      }
      unless sealed
        if SecureEvidence::AttachmentAccess.discard_allowed?(attachment, actor: @viewer)
          result[:discard_url] = @routes.secure_evidence_attachment_path(attachment)
        end
      end
      result
    end

    def localized(value)
      I18n.l(value, format: :long) if value
    end
  end
end

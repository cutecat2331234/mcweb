# frozen_string_literal: true

module Community
  class ReporterReportSerializer
    SAFE_TARGET_KINDS = {
      "Community::Topic" => "topic",
      "Community::Post" => "post",
      "Community::Message" => "private_message",
      "Community::ProfilePost" => "profile_post",
      "Community::ProfilePostComment" => "profile_post_comment",
      "Commerce::Review" => "review",
      "User" => "user"
    }.freeze

    def initialize(report:, routes: Rails.application.routes.url_helpers)
      @report = report
      @routes = routes
    end

    def summary
      {
        id: @report.public_id,
        public_id: @report.public_id,
        target_label: target_label,
        reason_label: @report.reason_label,
        reason_detail: reason_detail,
        status: @report.status,
        public_outcome_code: @report.public_outcome_code,
        submitted_at: I18n.l(@report.created_at, format: :long),
        state_changed_at: I18n.l(@report.state_changed_at, format: :long),
        lock_version: @report.lock_version,
        detail_url: @routes.forum_report_path(@report),
        can_supplement: @report.pending?,
        can_withdraw: @report.pending?
      }
    end

    def detail
      summary.merge(
        index_url: @routes.forum_reports_path,
        supplement_url: @routes.supplements_forum_report_path(@report),
        withdraw_url: @routes.withdraw_forum_report_path(@report),
        evidence_url: @routes.evidence_forum_report_path(@report),
        evidence_subject: {
          key: "community.report",
          public_id: @report.public_id
        },
        evidence_attachments: evidence_attachments,
        appeal_roles: eligible_appeal_roles,
        appeal_draft_url: @routes.appeal_draft_forum_report_path(@report),
        appeals_url: @routes.forum_report_appeals_path,
        supplements: @report.supplements.order(:created_at, :id).map do |supplement|
          {
            id: supplement.id,
            body: supplement.body,
            created_at: I18n.l(supplement.created_at, format: :long)
          }
        end
      )
    end

    def safe_target_label
      target_label
    end

    private

    def target_label
      kind = SAFE_TARGET_KINDS.fetch(@report.reportable_type, "content")
      I18n.t("mcweb.forum.reports.targets.#{kind}")
    end

    def reason_detail
      detail = @report.reason.to_s
      return if @report.reason_code.present? && detail == @report.reason_code

      detail.presence
    end

    def evidence_attachments
      sealed_links = @report.evidence_links.includes(attachment: :upload_record).order(:created_at, :id)
      sealed_ids = sealed_links.map(&:secure_evidence_attachment_id)
      unsealed = SecureEvidence::Attachment
        .where(
          subject_key: "community.report",
          subject_id: @report.id,
          subject_public_id: @report.public_id,
          uploader_id: @report.reporter_id
        )
        .where.not(id: sealed_ids)
        .where.not(state: "purged")
        .includes(:upload_record)
        .order(:created_at, :id)

      sealed_links.map { |link| evidence_attachment_payload(link.attachment, sealed: true) } +
        unsealed.map { |attachment| evidence_attachment_payload(attachment, sealed: false) }
    end

    def evidence_attachment_payload(attachment, sealed:)
      payload = {
        public_id: attachment.public_id,
        filename: attachment.filename,
        byte_size: attachment.byte_size,
        sha256: attachment.sha256,
        state: attachment.state,
        scan_status: attachment.upload_record&.scan_status,
        scan_status_url: @routes.scan_status_secure_evidence_attachment_path(attachment),
        download_url: @routes.secure_evidence_attachment_path(attachment),
        sealed:
      }
      unless sealed
        if SecureEvidence::AttachmentAccess.discard_allowed?(attachment, actor: @report.reporter)
          payload[:discard_url] = @routes.secure_evidence_attachment_path(attachment)
        end
      end
      payload
    end

    def eligible_appeal_roles
      roles = Community::ReportAppealPolicy.new(@report.reporter).eligible_roles(@report)
      active_roles = Community::ReportAppeal.active
        .where(report: @report, appellant: @report.reporter, appellant_role: roles)
        .pluck(:appellant_role)
      roles - active_roles
    end
  end
end

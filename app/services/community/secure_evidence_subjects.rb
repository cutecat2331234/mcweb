# frozen_string_literal: true

module Community
  module SecureEvidenceSubjects
    ALLOWED_EXTENSIONS = Community::AllowedAttachmentTypes::DEFAULT_EXTENSIONS.freeze
    RETENTION = 2.years

    REGISTRAR = lambda do |registry|
      registry.register(
        key: "community.report",
        model_name: "Community::Report",
        resolver: ->(public_id:) { Community::Report.find_by(public_id:) },
        upload_authorizer: ->(actor:, subject:) { report_upload_allowed?(actor:, report: subject) },
        download_authorizer: lambda { |actor:, subject:, attachment:|
          report_download_allowed?(actor:, report: subject, attachment:)
        },
        discard_authorizer: lambda { |actor:, subject:, attachment:|
          report_discard_allowed?(actor:, report: subject, attachment:)
        },
        retention: ->(subject:, attached_at:) { retention_until(subject:, attached_at:) },
        max_files: ReportEvidenceBinder::MAX_ATTACHMENTS,
        max_file_bytes: 10.megabytes,
        max_total_bytes: 50.megabytes,
        allowed_extensions: ALLOWED_EXTENSIONS
      )
      registry.register(
        key: "community.report_appeal",
        model_name: "Community::ReportAppeal",
        resolver: ->(public_id:) { Community::ReportAppeal.find_by(public_id:) },
        upload_authorizer: ->(actor:, subject:) { appeal_upload_allowed?(actor:, appeal: subject) },
        download_authorizer: lambda { |actor:, subject:, attachment:|
          appeal_download_allowed?(actor:, appeal: subject, attachment:)
        },
        discard_authorizer: lambda { |actor:, subject:, attachment:|
          appeal_discard_allowed?(actor:, appeal: subject, attachment:)
        },
        retention: ->(subject:, attached_at:) { retention_until(subject:, attached_at:) },
        max_files: ReportEvidenceBinder::MAX_ATTACHMENTS,
        max_file_bytes: 10.megabytes,
        max_total_bytes: 50.megabytes,
        allowed_extensions: ALLOWED_EXTENSIONS
      )
    end

    module_function

    def report_upload_allowed?(actor:, report:)
      return false unless actor&.session_eligible? && report&.persisted? && report.pending?

      actor.id == report.reporter_id
    end

    def report_download_allowed?(actor:, report:, attachment:)
      return false unless actor&.session_eligible? && report&.persisted?
      return false unless attachment_matches?(attachment, key: "community.report", subject: report)

      actor.id == report.reporter_id || ReportAppealPolicy.new(actor).report_visible_to_reviewer?(report)
    end

    def report_discard_allowed?(actor:, report:, attachment:)
      actor&.persisted? == true &&
        report&.persisted? &&
        actor.id == report.reporter_id &&
        attachment_matches?(attachment, key: "community.report", subject: report) &&
        !Community::ReportAttachment.exists?(secure_evidence_attachment_id: attachment.id)
    end

    def appeal_upload_allowed?(actor:, appeal:)
      return false unless actor&.session_eligible? && appeal&.persisted?

      if appeal.appellant_id == actor.id
        appeal.draft? && !appeal.draft_expired?
      else
        appeal.submitted? || appeal.under_review? ? ReportAppealPolicy.new(actor).reviewer_visible?(appeal) : false
      end
    end

    def appeal_download_allowed?(actor:, appeal:, attachment:)
      return false unless actor&.session_eligible? && appeal&.persisted?
      return false unless attachment_matches?(attachment, key: "community.report_appeal", subject: appeal)
      if appeal.appellant_id == actor.id
        link = Community::ReportAppealAttachment.find_by(secure_evidence_attachment_id: attachment.id)
        return attachment.uploader_id == actor.id unless link

        return link.forum_report_appeal_id == appeal.id && link.audience_appellant?
      end

      ReportAppealPolicy.new(actor).reviewer_visible?(appeal)
    end

    def appeal_discard_allowed?(actor:, appeal:, attachment:)
      return false unless attachment_matches?(attachment, key: "community.report_appeal", subject: appeal)
      return false if Community::ReportAppealAttachment.exists?(secure_evidence_attachment_id: attachment.id)

      if appeal.appellant_id == actor.id
        true
      else
        !appeal.draft? && ReportAppealPolicy.new(actor).reviewer_visible?(appeal)
      end
    end

    def retention_until(subject:, attached_at:)
      terminal_at = if subject.respond_to?(:decided_at)
        subject.decided_at || subject.cancelled_at
      elsif subject.respond_to?(:reviewed_at)
        subject.reviewed_at || subject.withdrawn_at
      end
      [ attached_at + RETENTION, terminal_at && terminal_at + RETENTION ].compact.max
    end

    def attachment_matches?(attachment, key:, subject:)
      attachment&.subject_key == key &&
        attachment.subject_id == subject.id &&
        attachment.subject_public_id == subject.public_id
    end
    private_class_method :attachment_matches?
  end
end

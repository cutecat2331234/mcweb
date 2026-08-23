# frozen_string_literal: true

module Commerce
  module SecureEvidenceSubjects
    SUBJECT_KEY = "commerce.dispute"
    MAX_ATTACHMENTS = 10
    MAX_FILE_BYTES = 10.megabytes
    MAX_TOTAL_BYTES = 50.megabytes
    ALLOWED_EXTENSIONS = Community::AllowedAttachmentTypes::DEFAULT_EXTENSIONS.freeze

    REGISTRAR = lambda do |registry|
      registry.register(
        key: SUBJECT_KEY,
        model_name: "Commerce::Dispute",
        resolver: ->(public_id:) { Commerce::Dispute.find_by(public_id:) },
        upload_authorizer: lambda { |actor:, subject:|
          upload_allowed?(actor:, dispute: subject)
        },
        download_authorizer: lambda { |actor:, subject:, attachment:|
          download_allowed?(actor:, dispute: subject, attachment:)
        },
        retention: lambda { |subject:, attached_at:|
          retention_until(dispute: subject, attached_at:)
        },
        max_files: MAX_ATTACHMENTS,
        max_file_bytes: MAX_FILE_BYTES,
        max_total_bytes: MAX_TOTAL_BYTES,
        allowed_extensions: ALLOWED_EXTENSIONS
      )
    end

    module_function

    def upload_allowed?(actor:, dispute:)
      Commerce::Disputes::CustomerPolicy.evidence_allowed?(
        dispute:,
        actor:
      )
    end

    def download_allowed?(actor:, dispute:, attachment:)
      return false unless actor&.session_eligible? && dispute&.persisted?
      return false unless attachment_matches?(attachment, dispute:)

      if dispute.order.user_id == actor.id
        attachment.uploader_id == actor.id
      else
        actor.permission?("store.disputes.sensitive_read")
      end
    end

    def retention_until(dispute:, attached_at:)
      [
        attached_at + Commerce::Dispute::RETENTION_PERIOD,
        dispute.retention_until
      ].compact.max
    end

    def attachment_matches?(attachment, dispute:)
      attachment&.subject_key == SUBJECT_KEY &&
        attachment.subject_id == dispute.id &&
        attachment.subject_public_id == dispute.public_id
    end
    private_class_method :attachment_matches?
  end
end

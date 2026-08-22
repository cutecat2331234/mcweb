# frozen_string_literal: true

module SecureEvidence
  module AttachmentAccess
    module_function

    def upload_allowed?(entry:, actor:, subject:)
      actor&.persisted? == true &&
        SubjectPolicy.upload_allowed?(entry:, actor:, subject:)
    end

    def subject_download_allowed?(attachment, actor:, catalog: SubjectCatalog)
      return false unless actor&.persisted?

      entry = catalog.entry_for_key(attachment.subject_key)
      return false unless entry

      subject = SubjectPolicy.resolve(entry:, public_id: attachment.subject_public_id)
      return false unless subject && subject.id == attachment.subject_id

      SubjectPolicy.download_allowed?(entry:, actor:, subject:, attachment:)
    rescue StandardError => error
      Rails.logger.warn(
        "[SecureEvidence::AttachmentAccess] access denied " \
        "attachment_id=#{attachment.id} error=#{error.class}"
      )
      false
    end

    def download_allowed?(attachment, actor:, catalog: SubjectCatalog)
      return false unless attachment.state_available?
      return false unless subject_download_allowed?(attachment, actor:, catalog:)

      upload = attachment.upload_record
      upload&.status_linked? == true && upload.scan_clean? && upload.blob.present?
    end
  end
end

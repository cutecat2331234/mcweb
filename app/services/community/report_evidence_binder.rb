# frozen_string_literal: true

module Community
  module ReportEvidenceBinder
    MAX_ATTACHMENTS = 10

    module_function

    def lock_clean!(subject_key:, subject:, actor:, public_ids:)
      ids = Array(public_ids).map { |value| value.to_s.strip }.reject(&:blank?).uniq
      raise BindingError, "report_evidence_limit_exceeded" if ids.size > MAX_ATTACHMENTS
      return [] if ids.empty?

      candidates = SecureEvidence::Attachment.where(public_id: ids).pluck(:id, :public_id)
      raise BindingError, "report_evidence_unavailable" unless candidates.size == ids.size

      attachment_ids = candidates.map(&:first).sort
      uploads = Community::Upload
        .where(secure_evidence_attachment_id: attachment_ids)
        .order(:id)
        .lock
        .to_a
        .index_by(&:secure_evidence_attachment_id)
      attachments = SecureEvidence::Attachment.where(id: attachment_ids).order(:id).lock.to_a
      raise BindingError, "report_evidence_unavailable" unless attachments.size == ids.size

      attachments.each do |attachment|
        upload = uploads[attachment.id]
        valid = attachment.subject_key == subject_key &&
          attachment.subject_id == subject.id &&
          attachment.subject_public_id == subject.public_id &&
          attachment.uploader_id == actor.id &&
          attachment.state_available? &&
          upload&.kind_secure_evidence_attachment? &&
          upload&.status_linked? &&
          upload&.scan_clean? &&
          upload&.blob&.present?
        raise BindingError, "report_evidence_not_clean" unless valid

        if Community::ReportAttachment.exists?(secure_evidence_attachment_id: attachment.id) ||
            Community::ReportAppealAttachment.exists?(secure_evidence_attachment_id: attachment.id)
          raise BindingError, "report_evidence_already_sealed"
        end
      end

      by_public_id = attachments.index_by(&:public_id)
      ids.map { |public_id| by_public_id.fetch(public_id) }
    end

    class BindingError < StandardError
      attr_reader :code

      def initialize(code)
        @code = code
        super(code)
      end
    end
  end
end

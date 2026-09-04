# frozen_string_literal: true

module SecureEvidence
  module IdentityLifecycle
    class DataExportContributor
      def self.call(context:)
        scope = Attachment.where(uploader: context.user).includes(:upload_record).order(:id)
        records = ::Identity::DataExporting::RecordSerializer.stream_relation(scope) do |attachment|
          upload = attachment.upload_record
          {
            "public_id" => attachment.public_id,
            "subject_key" => attachment.subject_key,
            "subject_public_id" => attachment.subject_public_id,
            "uploader_public_id" => attachment.uploader_public_id_snapshot,
            "filename" => attachment.filename,
            "content_type" => attachment.content_type,
            "byte_size" => attachment.byte_size,
            "sha256" => attachment.sha256,
            "state" => attachment.state,
            "scan_status" => upload&.scan_status,
            "scanned_at" => attachment.scanned_at&.iso8601,
            "retention_until" => attachment.retention_until.iso8601,
            "quarantined_at" => attachment.quarantined_at&.iso8601,
            "purged_at" => attachment.purged_at&.iso8601,
            "created_at" => attachment.created_at.iso8601
          }.compact
        end
        events = ::Identity::DataExporting::RecordSerializer.stream_relation(
          AttachmentEvent
            .joins(:attachment)
            .where(secure_evidence_attachments: { uploader_id: context.user.id })
            .includes(:attachment)
            .order(:id)
        ) do |event|
          {
            "attachment_public_id" => event.attachment.public_id,
            "type" => event.event_type,
            "occurred_at" => event.occurred_at.iso8601
          }
        end

        ::Identity::DataExporting::Contribution.new(
          documents: {
            "secure_evidence/attachments.json" => records,
            "secure_evidence/attachment-events.json" => events
          }
        )
      end
    end
  end
end

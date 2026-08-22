# frozen_string_literal: true

module SecureEvidence
  module IdentityLifecycle
    class DataExportContributor
      def self.call(context:)
        records = Attachment.where(uploader: context.user).order(:id).map do |attachment|
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
            "scanner" => upload&.scanner,
            "scan_result_code" => upload&.scan_result_code,
            "scanned_at" => attachment.scanned_at&.iso8601,
            "retention_until" => attachment.retention_until.iso8601,
            "quarantined_at" => attachment.quarantined_at&.iso8601,
            "purged_at" => attachment.purged_at&.iso8601,
            "created_at" => attachment.created_at.iso8601,
            "events" => attachment.events.timeline.map do |event|
              {
                "type" => event.event_type,
                "occurred_at" => event.occurred_at.iso8601
              }
            end
          }.compact
        end

        ::Identity::DataExporting::Contribution.new(
          documents: { "secure_evidence/attachments.json" => records }
        )
      end
    end
  end
end

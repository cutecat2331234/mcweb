# frozen_string_literal: true

module SecureEvidence
  module SyncCleanupResult
    module_function

    def completed!(
      attachment_id:,
      upload:,
      expected_cleanup_attempt:,
      expected_blob_id:,
      at: Time.current
    )
      attachment = Attachment.lock.find(attachment_id)
      validate_cleanup_claim!(
        attachment:,
        upload:,
        expected_cleanup_attempt:,
        expected_blob_id:
      )
      return attachment if attachment.state_upload_failed?

      purged!(attachment_id:, upload:, at:)
    end

    def purged!(attachment_id:, upload:, at: Time.current)
      attachment = Attachment.lock.find(attachment_id)
      return attachment if attachment.state_purged?
      unless attachment.state_purge_pending?
        attachment.errors.add(:state, :invalid)
        raise ActiveRecord::RecordInvalid, attachment
      end

      attachment.update!(state: "purged", purged_at: at)
      EventRecorder.record!(
        attachment:,
        event_type: "purged",
        idempotency_key: "evidence:purged:#{attachment.id}:#{upload.cleanup_attempts}",
        at:
      )
      attachment
    end

    def failed!(
      attachment_id:,
      upload:,
      expected_cleanup_attempt:,
      expected_blob_id:,
      error:,
      at: Time.current
    )
      attachment = Attachment.lock.find(attachment_id)
      validate_cleanup_claim!(
        attachment:,
        upload:,
        expected_cleanup_attempt:,
        expected_blob_id:
      )
      EventRecorder.record!(
        attachment:,
        event_type: "cleanup_failed",
        idempotency_key: "evidence:cleanup-failed:#{attachment.id}:#{upload.cleanup_attempts}",
        metadata: { failure_code: error.class.name.to_s.first(120) },
        at:
      )
      attachment
    end

    def validate_cleanup_claim!(
      attachment:,
      upload:,
      expected_cleanup_attempt:,
      expected_blob_id:
    )
      return if upload.status_cleanup_pending? &&
        upload.cleanup_attempts == expected_cleanup_attempt &&
        upload.active_storage_blob_id == expected_blob_id &&
        upload.secure_evidence_attachment_id == attachment.id

      attachment.errors.add(:base, :invalid)
      raise ActiveRecord::RecordInvalid, attachment
    end
    private_class_method :validate_cleanup_claim!
  end
end

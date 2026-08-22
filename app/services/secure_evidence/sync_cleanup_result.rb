# frozen_string_literal: true

module SecureEvidence
  module SyncCleanupResult
    module_function

    def purged!(attachment_id:, upload:, at: Time.current)
      attachment = Attachment.lock.find(attachment_id)
      return attachment if attachment.state_purged?

      attachment.update!(state: "purged", purged_at: at)
      EventRecorder.record!(
        attachment:,
        event_type: "purged",
        idempotency_key: "evidence:purged:#{attachment.id}:#{upload.cleanup_attempts}",
        at:
      )
      attachment
    end

    def failed!(attachment_id:, upload:, error:, at: Time.current)
      attachment = Attachment.lock.find(attachment_id)
      EventRecorder.record!(
        attachment:,
        event_type: "cleanup_failed",
        idempotency_key: "evidence:cleanup-failed:#{attachment.id}:#{upload.cleanup_attempts}",
        metadata: { failure_code: error.class.name.to_s.first(120) },
        at:
      )
      attachment
    end
  end
end

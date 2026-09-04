# frozen_string_literal: true

module SecureEvidence
  module SyncUploadResult
    module_function

    def stored!(attachment:, upload:, at: Time.current)
      validate_current_attempt!(attachment:, upload:)
      invalid_state!(attachment) unless attachment.state_uploading?
      attempt = upload_attempt(upload)

      attachment.update!(state: "pending")
      EventRecorder.record!(
        attachment:,
        actor: attachment.uploader,
        event_type: "upload_stored",
        idempotency_key: "evidence:upload-stored:#{attachment.id}:#{attempt}",
        metadata: { upload_attempt: attempt },
        at:
      )
      attachment
    end

    def failed!(attachment:, upload:, failure_code:, at: Time.current)
      validate_current_attempt!(attachment:, upload:)
      return attachment if attachment.state_upload_failed?
      invalid_state!(attachment) unless attachment.state_uploading?
      attempt = upload_attempt(upload)

      attachment.update!(state: "upload_failed")
      EventRecorder.record!(
        attachment:,
        actor: attachment.uploader,
        event_type: "upload_failed",
        idempotency_key: "evidence:upload-failed:#{attachment.id}:#{attempt}",
        metadata: {
          upload_attempt: attempt,
          failure_code: failure_code.to_s.first(120)
        },
        at:
      )
      attachment
    end

    def retried!(attachment:, upload:, at: Time.current)
      validate_current_attempt!(attachment:, upload:)
      invalid_state!(attachment) unless attachment.state_upload_failed?
      attempt = upload_attempt(upload)

      attachment.update!(state: "uploading")
      EventRecorder.record!(
        attachment:,
        actor: attachment.uploader,
        event_type: "upload_retried",
        idempotency_key: "evidence:upload-retried:#{attachment.id}:#{attempt}",
        metadata: { upload_attempt: attempt },
        at:
      )
      attachment
    end

    def validate_current_attempt!(attachment:, upload:)
      return if upload.kind_secure_evidence_attachment? &&
        upload.secure_evidence_attachment_id == attachment.id

      attachment.errors.add(:base, :invalid)
      raise ActiveRecord::RecordInvalid, attachment
    end
    private_class_method :validate_current_attempt!

    def upload_attempt(upload)
      "#{upload.id}.#{upload.cleanup_attempts}"
    end
    private_class_method :upload_attempt

    def invalid_state!(attachment)
      attachment.errors.add(:state, :invalid)
      raise ActiveRecord::RecordInvalid, attachment
    end
    private_class_method :invalid_state!
  end
end

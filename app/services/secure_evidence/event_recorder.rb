# frozen_string_literal: true

module SecureEvidence
  module EventRecorder
    class AuditFailure < StandardError; end

    module_function

    def record!(attachment:, event_type:, idempotency_key:, actor: nil, metadata: {}, at: Time.current)
      event_metadata = sanitize_metadata(metadata)
      AttachmentEvent.transaction(requires_new: true) do
        existing = AttachmentEvent.find_by(idempotency_key: idempotency_key)
        if existing
          next validate_existing!(
            existing,
            attachment:,
            event_type:,
            actor:,
            metadata: event_metadata
          )
        end

        event = AttachmentEvent.create!(
          attachment:,
          actor:,
          event_type:,
          idempotency_key:,
          metadata: event_metadata,
          occurred_at: at,
          created_at: at
        )
        audit = Administration::AuditLogger.call(
          actor:,
          action: "secure_evidence.#{event_type}",
          resource: attachment,
          request_id: idempotency_key,
          metadata: {
            event_id: event.id,
            subject_key: attachment.subject_key,
            state: attachment.state,
            byte_size: attachment.byte_size
          }.merge(event_metadata)
        )
        raise AuditFailure, "secure_evidence_audit_failed" unless audit.success?

        event
      end
    rescue ActiveRecord::RecordNotUnique
      validate_existing!(
        AttachmentEvent.find_by!(idempotency_key: idempotency_key),
        attachment:,
        event_type:,
        actor:,
        metadata: event_metadata
      )
    end

    def sanitize_metadata(metadata)
      metadata.to_h.stringify_keys.slice(
        "scan_attempt",
        "scanner",
        "result_code",
        "retention_until",
        "previous_retention_until",
        "download_request_id",
        "failure_code",
        "upload_attempt"
      ).compact
    end
    private_class_method :sanitize_metadata

    def validate_existing!(event, attachment:, event_type:, actor:, metadata:)
      if event.secure_evidence_attachment_id != attachment.id ||
          event.event_type != event_type.to_s ||
          event.actor_id != actor&.id ||
          event.metadata != metadata
        raise ArgumentError, "secure_evidence_event_idempotency_conflict"
      end

      event
    end
    private_class_method :validate_existing!
  end
end

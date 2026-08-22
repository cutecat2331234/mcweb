# frozen_string_literal: true

module SecureEvidence
  module SyncScanResult
    module_function

    def call!(upload:, status:, scanner:, result_code:, scan_attempt:, retryable: nil, at: Time.current)
      attachment = upload.secure_evidence_attachment
      raise ActiveRecord::RecordNotFound, "secure_evidence_attachment_missing" unless attachment

      attachment.lock!
      attributes = state_attributes(status:, retryable:, at:)
      attachment.update!(attributes)
      EventRecorder.record!(
        attachment:,
        event_type: event_type(status),
        idempotency_key: "evidence:scan:#{upload.id}:#{scan_attempt}:#{status}",
        metadata: {
          scan_attempt:,
          scanner: scanner.to_s.first(80),
          result_code: result_code.to_s.first(120)
        },
        at:
      )
      attachment
    end

    def state_attributes(status:, retryable:, at:)
      case status.to_sym
      when :clean
        { state: "available", scanned_at: at, quarantined_at: nil }
      when :infected
        { state: "quarantined", scanned_at: at, quarantined_at: at }
      when :error
        if retryable
          { state: "pending", scanned_at: at, quarantined_at: nil }
        else
          { state: "quarantined", scanned_at: at, quarantined_at: at }
        end
      else
        raise ArgumentError, "secure_evidence_scan_status_invalid"
      end
    end
    private_class_method :state_attributes

    def event_type(status)
      {
        clean: "scan_clean",
        infected: "scan_infected",
        error: "scan_error"
      }.fetch(status.to_sym)
    end
    private_class_method :event_type
  end
end

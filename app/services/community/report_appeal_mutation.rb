# frozen_string_literal: true

module Community
  module ReportAppealMutation
    module_function

    def fingerprint(payload)
      Digest::SHA256.hexdigest(ActiveSupport::JSON.encode(canonicalize(payload)))
    end

    def canonicalize(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), result|
          result[key.to_s] = canonicalize(nested)
        end.sort.to_h
      when Array
        value.map { |nested| canonicalize(nested) }
      else
        value
      end
    end
    private_class_method :canonicalize

    def secure_match?(left, right)
      left = left.to_s
      right = right.to_s
      left.bytesize == right.bytesize && ActiveSupport::SecurityUtils.secure_compare(left, right)
    end

    def record_event!(appeal:, actor:, event_type:, from_status:, to_status:,
                      idempotency_key_digest:, request_fingerprint:, public_outcome_code: nil,
                      occurred_at: Time.current)
      Community::ReportAppealEvent.create!(
        appeal:,
        actor:,
        event_type:,
        from_status:,
        to_status:,
        public_outcome_code:,
        idempotency_key_digest:,
        request_fingerprint:,
        occurred_at:,
        created_at: occurred_at
      )
    end

    def failure(code)
      ServiceResult.failure(error: code, code:)
    end
  end
end

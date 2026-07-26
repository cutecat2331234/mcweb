# frozen_string_literal: true

require "digest"

module Community
  module ContentIdempotency
    KEY_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._:-]{0,127}\z/
    INVALID_KEY_ERROR = "idempotency_key_invalid"
    REUSED_KEY_ERROR = "idempotency_key_reused"

    module_function

    def claim(user:, operation:, key:, payload:)
      normalized_key = normalize_key(key)
      return ServiceResult.failure(error: INVALID_KEY_ERROR) if normalized_key == false
      return ServiceResult.success(request: nil, replay: false, resource: nil) unless normalized_key

      fingerprint = fingerprint(payload)
      request = Community::ContentRequest.create_or_find_by!(
        user: user,
        operation: operation,
        key_digest: Digest::SHA256.hexdigest(normalized_key)
      ) do |created|
        created.request_fingerprint = fingerprint
      end
      request.lock!

      unless secure_fingerprint_match?(request.request_fingerprint, fingerprint)
        return ServiceResult.failure(error: REUSED_KEY_ERROR)
      end

      resource = request.resource
      ServiceResult.success(request: request, replay: resource.present?, resource: resource)
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    end

    def fingerprint(payload)
      Digest::SHA256.hexdigest(JSON.generate(canonicalize(payload)))
    end

    def normalize_key(value)
      key = value.to_s.strip
      return nil if key.blank?
      return false unless KEY_PATTERN.match?(key)

      key
    end

    def canonicalize(value)
      case value
      when Hash
        value.to_h
          .transform_keys(&:to_s)
          .sort_by { |key, _| key }
          .to_h
          .transform_values { |nested| canonicalize(nested) }
      when Array
        value.map { |nested| canonicalize(nested) }
      when Time, DateTime
        value.iso8601(6)
      else
        value
      end
    end
    private_class_method :canonicalize

    def secure_fingerprint_match?(stored, expected)
      return false unless stored.to_s.bytesize == expected.bytesize

      ActiveSupport::SecurityUtils.secure_compare(stored, expected)
    end
    private_class_method :secure_fingerprint_match?
  end
end

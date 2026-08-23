# frozen_string_literal: true

module Website
  module LifecycleContract
    IDEMPOTENCY_PATTERN = /\A[A-Za-z0-9_.:-]{8,128}\z/
    MAX_REASON_LENGTH = 1_000
    DEFAULT_RETENTION_DAYS = 30
    MAX_RETENTION_DAYS = 3_650

    private

    def normalize_reason!(value)
      reason = value.to_s.strip
      raise LifecycleError, "website_content_reason_required" if reason.blank?
      if reason.length > MAX_REASON_LENGTH
        raise LifecycleError, "website_content_reason_too_long"
      end

      reason
    end

    def normalize_idempotency_key!(value)
      key = value.to_s.strip
      unless key.match?(IDEMPOTENCY_PATTERN)
        raise LifecycleError, "website_content_idempotency_key_invalid"
      end

      key
    end

    def idempotency_digest(value)
      Digest::SHA256.hexdigest(value)
    end

    def revision_replayed?(content, request_id, event_type, operation_digest:)
      return false if request_id.blank?

      revision = content.revisions.find_by(request_id_digest: idempotency_digest(request_id))
      return false unless revision
      if revision.event_type != event_type.to_s ||
          !secure_digest_match?(revision.operation_digest, operation_digest)
        raise LifecycleError, "website_content_idempotency_key_reused"
      end

      true
    end

    def operation_digest(value)
      Digest::SHA256.hexdigest(JSON.generate(canonical_operation_value(value)))
    end

    def expected_version!(value)
      version = Integer(value, exception: false)
      raise LifecycleError, "website_content_version_required" if version.nil? || version.negative?

      version
    end

    def assert_version!(content, expected)
      return if content.lock_version == expected

      raise LifecycleError.new(
        "website_content_conflict",
        current_lock_version: content.lock_version
      )
    end

    def lock_content(content)
      content.class.with_lifecycle.lock.find(content.id)
    end

    def retention_days
      raw = Integer(
        SiteSetting.get("website.content_recovery.retention_days", DEFAULT_RETENTION_DAYS),
        exception: false
      )
      raw = DEFAULT_RETENTION_DAYS unless raw&.between?(1, MAX_RETENTION_DAYS)
      raw
    end

    def failure(error)
      ServiceResult.failure(
        error: error.code,
        code: error.code,
        value: error.details
      )
    end

    def audit!(**attributes)
      result = Administration::AuditLogger.call(**attributes)
      raise LifecycleError, "website_content_audit_failed" unless result.success?

      result.value
    end

    def secure_digest_match?(left, right)
      left = left.to_s
      right = right.to_s
      left.bytesize == right.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(left, right)
    end

    def canonical_operation_value(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), canonical|
          canonical[key.to_s] = canonical_operation_value(nested)
        end.sort.to_h
      when Array
        value.map { |nested| canonical_operation_value(nested) }
      when ActiveSupport::TimeWithZone, Time, DateTime
        value.iso8601(6)
      when Date
        value.iso8601
      when Symbol
        value.to_s
      else
        value
      end
    end
  end
end

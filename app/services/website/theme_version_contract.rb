# frozen_string_literal: true

module Website
  module ThemeVersionContract
    IDEMPOTENCY_PATTERN = /\A[A-Za-z0-9_.:-]{8,128}\z/
    MAX_REASON_LENGTH = 1_000
    TIMESTAMP_INCREMENT_SECONDS = Rational(1, 1_000_000)

    private

    def normalize_theme_reason!(value)
      reason = value.to_s.strip
      raise LifecycleError, "website_theme_reason_required" if reason.blank?
      if reason.length > MAX_REASON_LENGTH
        raise LifecycleError, "website_theme_reason_too_long"
      end
      reason
    end

    def normalize_theme_idempotency_key!(value)
      key = value.to_s.strip
      unless key.match?(IDEMPOTENCY_PATTERN)
        raise LifecycleError, "website_theme_idempotency_key_invalid"
      end
      key
    end

    def theme_expected_version!(value)
      version = Integer(value, exception: false)
      if version.nil? || version.negative?
        raise LifecycleError, "website_theme_version_required"
      end
      version
    end

    def assert_theme_version!(theme, expected)
      return if theme.lock_version == expected

      raise LifecycleError.new(
        "website_theme_conflict",
        current_lock_version: theme.lock_version
      )
    end

    def theme_idempotency_digest(value)
      Digest::SHA256.hexdigest(value)
    end

    def theme_operation_digest(value)
      Digest::SHA256.hexdigest(JSON.generate(canonical_theme_value(value)))
    end

    def secure_theme_match?(left, right)
      left = left.to_s
      right = right.to_s
      left.bytesize == right.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(left, right)
    end

    def secure_theme_digest_match?(left, right)
      secure_theme_match?(left, right)
    end

    def theme_failure(error)
      ServiceResult.failure(error: error.code, code: error.code, value: error.details)
    end

    def record_theme_audit!(**attributes)
      result = Administration::AuditLogger.call(**attributes)
      raise LifecycleError, "website_theme_audit_failed" unless result.success?

      result.value
    end

    def safe_theme_state(theme)
      {
        name: theme.name,
        key: theme.key,
        active: theme.active?,
        token_count: count_theme_token_leaves(theme.tokens),
        lock_version: theme.lock_version
      }
    end

    def advance_theme_timestamp(theme)
      next_timestamp = theme.updated_at ? theme.updated_at + TIMESTAMP_INCREMENT_SECONDS : Time.current
      theme.updated_at = [ Time.current, next_timestamp ].max
    end

    def theme_changed_paths(before_snapshot, after_snapshot)
      ThemeRevisionDiff.call(
        before_snapshot: before_snapshot,
        after_snapshot: after_snapshot
      ).map { |change| change.fetch(:path) }
    end

    def count_theme_token_leaves(value)
      case value
      when Hash
        value.values.sum { |nested| count_theme_token_leaves(nested) }
      when Array
        value.sum { |nested| count_theme_token_leaves(nested) }
      else
        1
      end
    end

    def canonical_theme_value(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), canonical|
          canonical[key.to_s] = canonical_theme_value(nested)
        end.sort.to_h
      when Array
        value.map { |nested| canonical_theme_value(nested) }
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

# frozen_string_literal: true

module SecureEvidence
  module SubjectPolicy
    MIN_RETENTION = 1.hour
    MAX_RETENTION = 10.years
    PurgeGuardResult = Data.define(:allowed, :value)
    class PurgeGuardFailure < StandardError; end

    module_function

    def resolve(entry:, public_id:)
      normalized_id = public_id.to_s.strip
      return if normalized_id.blank? || normalized_id.bytesize > 255

      subject = entry.resolver.call(public_id: normalized_id)
      expected_model = entry.model_name.constantize
      return unless subject.is_a?(expected_model) && subject.persisted?
      return unless subject.id.to_i.positive?
      return unless subject.respond_to?(:public_id)
      return unless secure_match?(subject.public_id, normalized_id)

      subject
    rescue StandardError => error
      Rails.logger.warn(
        "[SecureEvidence::SubjectPolicy] subject resolution denied " \
        "key=#{entry.key} error=#{error.class}"
      )
      nil
    end

    def upload_allowed?(entry:, actor:, subject:)
      strict_authorization(entry.upload_authorizer, actor:, subject:)
    end

    def download_allowed?(entry:, actor:, subject:, attachment:)
      strict_authorization(entry.download_authorizer, actor:, subject:, attachment:)
    end

    def discard_allowed?(entry:, actor:, subject:, attachment:)
      return false unless entry.discard_authorizer

      strict_authorization(entry.discard_authorizer, actor:, subject:, attachment:)
    end

    # Product editions can serialize their own preservation decision with the
    # CE attachment transition without introducing an upstream dependency.
    # The guard must explicitly invoke the supplied operation once to permit
    # cleanup; returning without doing so denies it.
    def with_purge_guard(entry:, subject:, attachment:, now:)
      unless entry&.purge_guard
        return PurgeGuardResult.new(allowed: true, value: yield)
      end

      invoked = false
      operation_started = false
      guard_open = true
      guard_thread = Thread.current
      value = nil
      operation = lambda do
        unless guard_open && Thread.current.equal?(guard_thread)
          raise PurgeGuardFailure, "secure_evidence_purge_guard_expired"
        end
        raise PurgeGuardFailure, "secure_evidence_purge_guard_reused" if invoked

        invoked = true
        operation_started = true
        value = yield
      end
      entry.purge_guard.call(subject:, attachment:, now:, operation:)
      PurgeGuardResult.new(allowed: invoked, value:)
    rescue PurgeGuardFailure => error
      log_purge_guard_failure(entry:, error:)
      raise
    rescue StandardError => error
      raise if operation_started

      log_purge_guard_failure(entry:, error:)
      raise PurgeGuardFailure, "secure_evidence_purge_guard_failed"
    ensure
      guard_open = false
    end

    def retention_until(entry:, subject:, attached_at:)
      value = entry.retention.call(subject:, attached_at:)
      timestamp = value.respond_to?(:to_time) ? value.to_time : nil
      return unless timestamp
      return unless timestamp >= attached_at + MIN_RETENTION
      return unless timestamp <= attached_at + MAX_RETENTION

      timestamp
    rescue StandardError => error
      Rails.logger.warn(
        "[SecureEvidence::SubjectPolicy] retention resolution denied " \
        "key=#{entry.key} error=#{error.class}"
      )
      nil
    end

    def strict_authorization(callable, **arguments)
      callable.call(**arguments) == true
    rescue StandardError => error
      Rails.logger.warn(
        "[SecureEvidence::SubjectPolicy] authorization denied error=#{error.class}"
      )
      false
    end
    private_class_method :strict_authorization

    def log_purge_guard_failure(entry:, error:)
      Rails.logger.warn(
        "[SecureEvidence::SubjectPolicy] purge guard denied " \
        "key=#{entry&.key} error=#{error.class}"
      )
    end
    private_class_method :log_purge_guard_failure

    def secure_match?(left, right)
      left = left.to_s
      right = right.to_s
      left.bytesize == right.bytesize && ActiveSupport::SecurityUtils.secure_compare(left, right)
    end
    private_class_method :secure_match?
  end
end

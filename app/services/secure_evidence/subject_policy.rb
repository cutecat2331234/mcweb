# frozen_string_literal: true

module SecureEvidence
  module SubjectPolicy
    MIN_RETENTION = 1.hour
    MAX_RETENTION = 10.years

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

    def secure_match?(left, right)
      left = left.to_s
      right = right.to_s
      left.bytesize == right.bytesize && ActiveSupport::SecurityUtils.secure_compare(left, right)
    end
    private_class_method :secure_match?
  end
end

# frozen_string_literal: true

class ServiceResult
  attr_reader :value, :error, :errors, :code, :retry_after

  def initialize(success:, value: nil, error: nil, errors: nil, code: nil, retry_after: nil)
    @success = success
    @value = value
    @error = error
    @errors = errors || (error ? { base: [ error ] } : {})
    @code = code&.to_s
    @retry_after = retry_after&.to_i
  end

  def success?
    @success
  end

  def failure?
    !success?
  end

  def rate_limited?
    failure? && code == "rate_limited"
  end

  def self.success(value = nil)
    new(success: true, value: value)
  end

  def self.failure(error: nil, errors: nil, value: nil, code: nil, retry_after: nil)
    error = ServiceErrorTranslator.translate(error) if error.present?
    new(
      success: false,
      error: error,
      errors: errors,
      value: value,
      code: code,
      retry_after: retry_after
    )
  end
end

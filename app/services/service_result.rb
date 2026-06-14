# frozen_string_literal: true

class ServiceResult
  attr_reader :value, :error, :errors

  def initialize(success:, value: nil, error: nil, errors: nil)
    @success = success
    @value = value
    @error = error
    @errors = errors || (error ? { base: [ error ] } : {})
  end

  def success?
    @success
  end

  def failure?
    !success?
  end

  def self.success(value = nil)
    new(success: true, value: value)
  end

  def self.failure(error: nil, errors: nil)
    new(success: false, error: error, errors: errors)
  end
end

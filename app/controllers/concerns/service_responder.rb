# frozen_string_literal: true

module ServiceResponder
  extend ActiveSupport::Concern

  private

  def service_error_message(result)
    raw = if result.error.present?
      result.error
    elsif result.errors.blank?
      nil
    else
      result.errors.flat_map { |_, msgs| Array(msgs) }.join("；")
    end

    ServiceErrorTranslator.translate(raw)
  end

  def inertia_form_errors(result, prefix: nil)
    if result.error.present?
      return { base: ServiceErrorTranslator.translate(result.error) }
    end
    return {} if result.errors.blank?

    result.errors.each_with_object({}) do |(key, msgs), hash|
      path = prefix ? "#{prefix}.#{key}" : key.to_s
      hash[path] = ServiceErrorTranslator.translate(Array(msgs).join("；"))
    end
  end

  def flash_service_errors(result)
    flash.now[:alert] = service_error_message(result)
  end
end

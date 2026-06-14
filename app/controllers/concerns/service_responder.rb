# frozen_string_literal: true

module ServiceResponder
  extend ActiveSupport::Concern

  private

  def service_error_message(result)
    return result.error if result.error.present?
    return nil if result.errors.blank?

    result.errors.flat_map { |_, msgs| Array(msgs) }.join("；")
  end

  def flash_service_errors(result)
    flash.now[:alert] = service_error_message(result)
  end
end

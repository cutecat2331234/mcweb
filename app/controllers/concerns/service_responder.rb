# frozen_string_literal: true

module ServiceResponder
  extend ActiveSupport::Concern

  private

  def service_error_message(result)
    result.error.presence || result.errors.values.flatten.first
  end

  def flash_service_errors(result)
    flash.now[:alert] = service_error_message(result)
  end
end

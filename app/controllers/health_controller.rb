# frozen_string_literal: true

class HealthController < ApplicationController
  skip_before_action :redirect_to_setup_unless_locked
  skip_before_action :block_setup_when_locked

  def live
    render json: { status: "ok" }
  end

  def ready
    result = Operations::HealthChecker.call
    healthy = result.success? && result.value[:status] == "ok"

    if detailed_health_check_allowed?
      render json: result.value, status: healthy ? :ok : :service_unavailable
    else
      render json: { status: healthy ? "ok" : "degraded" }, status: healthy ? :ok : :service_unavailable
    end
  end

  private

  def detailed_health_check_allowed?
    return true if Rails.env.local?

    token = health_check_token
    return false if token.blank?

    ActiveSupport::SecurityUtils.secure_compare(
      request.headers["X-Health-Token"].to_s,
      token
    )
  end

  def health_check_token
    Mcweb::LocalConfig.load["health_check_token"].presence ||
      Rails.application.credentials.dig(:health, :token).to_s.presence
  end
end

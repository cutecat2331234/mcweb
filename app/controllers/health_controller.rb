# frozen_string_literal: true

class HealthController < ApplicationController
  skip_before_action :redirect_to_setup_unless_locked
  skip_before_action :block_setup_when_locked

  def live
    render json: { status: "ok" }.merge(developer_mode_health)
  end

  def ready
    result = Operations::HealthChecker.call
    healthy = result.success? && result.value[:status] == "ok"

    payload =
      if detailed_health_check_allowed?
        result.value
      else
        { status: healthy ? "ok" : "degraded" }
      end
    payload = payload.merge(developer_mode_health)

    render json: payload, status: healthy ? :ok : :service_unavailable
  end

  private

  def developer_mode_health
    enabled = Mcweb::DeveloperMode.enabled?
    {
      developer_mode: enabled,
      developer_mode_profile: enabled ? Mcweb::DeveloperMode.profile.to_s : nil,
      scheduled_jobs_auto_registration:
        Mcweb::SidekiqCronSchedule.automatic_registration_enabled?
    }
  end

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

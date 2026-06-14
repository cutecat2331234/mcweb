# frozen_string_literal: true

class HealthController < ApplicationController
  skip_before_action :redirect_to_setup_unless_locked
  skip_before_action :block_setup_when_locked

  def live
    render json: { status: "ok" }
  end

  def ready
    result = Operations::HealthChecker.call

    if result.success? && result.value[:status] == "ok"
      render json: result.value
    else
      render json: result.value || { status: "degraded" }, status: :service_unavailable
    end
  end
end

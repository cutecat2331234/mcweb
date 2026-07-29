# frozen_string_literal: true

class DeveloperModeToolsController < ApplicationController
  prepend_before_action :require_developer_mode!
  before_action :require_login
  before_action :require_persona_switch_access!

  def switch_persona
    persona = params[:persona].to_s
    unless User::DEVELOPER_MODE_PERSONAS.include?(persona)
      return redirect_back(
        fallback_location: Mcweb::Paths::APP_PREFIX,
        alert: t("mcweb.flash.developer_mode_persona_invalid")
      )
    end

    target = User.find_by(
      developer_mode_persona: persona,
      status: "active"
    )
    unless target&.session_eligible?
      return redirect_back(
        fallback_location: Mcweb::Paths::APP_PREFIX,
        alert: t("mcweb.flash.developer_mode_persona_unavailable")
      )
    end

    actor = current_user
    result = Identity::SessionManager.call(
      user: target,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      remember_me: false
    )
    unless result.success?
      return redirect_back(
        fallback_location: Mcweb::Paths::APP_PREFIX,
        alert: service_error_message(result)
      )
    end

    current_session&.revoke!
    reset_session
    @session_record = result.value.fetch(:session)
    @current_user = target
    sign_in(
      session_record: @session_record,
      token: result.value.fetch(:token)
    )

    Administration::AuditLogger.call(
      actor: actor,
      action: "developer_mode.persona_switched",
      resource: target,
      metadata: {
        from_persona: actor.developer_mode_persona.presence || "operator",
        to_persona: persona
      },
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      request_id: request.request_id
    )

    redirect_to Mcweb::Paths::APP_PREFIX,
      notice: t(
        "mcweb.flash.developer_mode_persona_switched",
        persona: t("mcweb.developer_mode.personas.#{persona}")
      )
  end

  private

  def require_developer_mode!
    head :not_found unless Mcweb::DeveloperMode.enabled?
  end

  def require_persona_switch_access!
    return if current_user.developer_mode_persona.present?
    return if current_user.permission?("system.settings.manage")

    head :forbidden
  end
end

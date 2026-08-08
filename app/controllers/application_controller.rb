class ApplicationController < ActionController::Base
  include Authentication
  include CsrfCookie
  include InstallationGuard
  include FeatureGuard
  include ServiceResponder
  include Pagy::Method
  include InertiaSerializable
  include InertiaSharedProps
  include BlockedUsersFilterable
  include TouchLastSeen
  include FrontendTemplateShare
  include LocaleSettable

  before_action :require_totp_setup
  before_action :enforce_plugin_maintenance_window
  before_action :reconcile_plugin_runtime_generation
  after_action :mark_developer_mode_response

  allow_browser versions: :modern,
    unless: -> { Mcweb::DeveloperMode.allow?(:skip_browser_policy) }

  stale_when_importmap_changes

  inertia_config layout: "inertia"

  inertia_share do
    build_inertia_shared_props
  end
  private

  def enforce_plugin_maintenance_window
    return unless defined?(PluginMaintenanceWindow)
    return if controller_path.start_with?("admin/", "setup/", "api/")
    return if controller_path == "identity/sessions"
    return if %w[health commerce/webhooks].include?(controller_path)
    return if current_user&.can_access_admin?
    return unless PluginMaintenanceWindow.active?

    response.set_header("Retry-After", "30")
    payload = {
      error: "plugin_maintenance",
      message: t("mcweb.plugin_maintenance.message")
    }
    if request.format.json?
      render json: payload, status: :service_unavailable
    else
      render(
        template: "shared/plugin_maintenance",
        layout: false,
        status: :service_unavailable,
        locals: payload
      )
    end
  rescue ActiveRecord::ActiveRecordError
    nil
  end

  def reconcile_plugin_runtime_generation
    Mcweb::Plugins.generation_coordinator.reconcile_current_process!(process_kind: "web")
  rescue StandardError => e
    Rails.logger.warn(
      "[mcweb.plugins] generation reconciliation skipped: #{e.class}: #{e.message}"
    )
  end

  def safe_local_path(path)
    safe_local_redirect_path(path, fallback: nil)
  end

  private

  def admin_demo_enabled?
    Mcweb::DeveloperMode.enabled?
  end

  def developer_mode_frontend_payload
    return { enabled: false } unless Mcweb::DeveloperMode.enabled?

    payload = {
      enabled: true,
      profile: Mcweb::DeveloperMode.profile,
      runtime_profile: Mcweb::DeveloperMode.runtime_profile,
      vite_profile: ViteRuby.config.mode,
      production_environment: Rails.env.production?,
      environment: Rails.env,
      request_id: request.request_id,
      workbench_access:
        current_user.present? &&
          current_user.can_access_admin? &&
          current_user.permission?("admin.access") &&
          current_user.permission?("system.settings.manage")
    }

    tools_access =
      current_user.present? &&
        (
          current_user.developer_mode_persona.present? ||
          current_user.permission?("system.settings.manage")
        )
    payload[:tools_access] = tools_access
    return payload unless tools_access

    available_personas = User
      .where(
        developer_mode_persona: User::DEVELOPER_MODE_PERSONAS,
        status: "active"
      )
      .pluck(:developer_mode_persona)
    payload.merge(
      current_persona:
        current_user.developer_mode_persona.presence || "operator",
      persona_switch_url: developer_mode_switch_persona_path,
      personas: User::DEVELOPER_MODE_PERSONAS.map do |persona|
        {
          key: persona,
          available: available_personas.include?(persona)
        }
      end
    )
  rescue ActiveRecord::ActiveRecordError
    payload
  end

  def mark_developer_mode_response
    return unless Mcweb::DeveloperMode.enabled?

    response.set_header("X-McWeb-Developer-Mode", "unrestricted")
    response.set_header(
      "X-McWeb-Runtime-Profile",
      Mcweb::DeveloperMode.runtime_profile.to_s
    )
    response.set_header("X-Robots-Tag", "noindex, nofollow")
    # Merge the developer-mode directive through Action Dispatch so endpoints
    # carrying authenticated or one-time data retain their existing `private`
    # classification. Replacing the header would silently weaken that contract.
    response.cache_control[:no_store] = true
  end

  # Turns a flat map of dotted i18n keys into a nested hash so vue-i18n can
  # merge it as locale messages. { "forum.top.title" => "x" } becomes
  # { "forum" => { "top" => { "title" => "x" } } }.
  def unflatten_phrase_overrides(flat)
    nested = {}
    Array(flat).each do |key, value|
      segments = key.to_s.split(".")
      next if segments.empty?

      cursor = nested
      segments[0...-1].each do |segment|
        existing = cursor[segment]
        cursor = (existing.is_a?(Hash) ? existing : (cursor[segment] = {}))
      end
      cursor[segments[-1]] = value
    end
    nested
  end
end

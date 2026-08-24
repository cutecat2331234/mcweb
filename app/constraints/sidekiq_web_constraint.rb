# frozen_string_literal: true

require "uri"

class SidekiqWebConstraint
  SESSION_COOKIE = :session_token
  READ_ONLY_METHODS = %w[GET HEAD].freeze
  LOCALE_PREFERENCE_PATH = "/jobs/change_locale"
  READ_PERMISSION = "system.sidekiq.read"
  MANAGE_PERMISSION = "system.sidekiq.manage"

  def self.matches?(request)
    token = request.cookie_jar.signed[SESSION_COOKIE].presence || request.session[SESSION_COOKIE].presence
    return false if token.blank?

    record = Session.find_by(token_digest: Session.digest_token(token))
    return false unless record&.active?
    return false if state_changing_request?(request) && !same_origin_request?(request)

    user = record.user
    return false unless user.session_eligible?
    return false if user.mandatory_totp_setup_pending?

    user.can_access_admin? &&
      user.permission?("admin.access") &&
      user.permission?(READ_PERMISSION) &&
      (!manage_permission_required?(request) || user.permission?(MANAGE_PERMISSION)) &&
      user.admin_module_allowed?("system")
  rescue StandardError
    false
  end

  def self.manage_permission_required?(request)
    method = request.request_method.to_s.upcase
    return false if READ_ONLY_METHODS.include?(method)
    return false if method == "POST" && request.path.to_s == LOCALE_PREFERENCE_PATH

    true
  end
  private_class_method :manage_permission_required?

  def self.state_changing_request?(request)
    !READ_ONLY_METHODS.include?(request.request_method.to_s.upcase)
  end
  private_class_method :state_changing_request?

  def self.same_origin_request?(request)
    expected_origin = normalized_origin(request.base_url)
    return false unless expected_origin

    fetch_site = request.get_header("HTTP_SEC_FETCH_SITE").to_s
    return false if fetch_site.present? && fetch_site != "same-origin"

    supplied_origin = request.get_header("HTTP_ORIGIN").to_s
    if supplied_origin.present?
      return normalized_origin(supplied_origin) == expected_origin
    end

    normalized_origin(request.referer) == expected_origin
  end
  private_class_method :same_origin_request?

  def self.normalized_origin(value)
    uri = URI.parse(value.to_s)
    return unless uri.is_a?(URI::HTTP) && uri.host.present?

    port = uri.port == uri.default_port ? "" : ":#{uri.port}"
    "#{uri.scheme.downcase}://#{uri.host.downcase}#{port}"
  rescue URI::InvalidURIError
    nil
  end
  private_class_method :normalized_origin
end

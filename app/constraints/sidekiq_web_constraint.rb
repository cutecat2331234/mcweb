# frozen_string_literal: true

class SidekiqWebConstraint
  SESSION_COOKIE = :session_token
  READ_ONLY_METHODS = %w[GET HEAD].freeze

  def self.matches?(request)
    token = request.cookie_jar.signed[SESSION_COOKIE].presence || request.session[SESSION_COOKIE].presence
    return false if token.blank?

    record = Session.find_by(token_digest: Session.digest_token(token))
    return false unless record&.active?

    user = record.user
    return false if user.deleted? || user.banned?

    user.can_access_admin? &&
      user.permission?("admin.access") &&
      user.permission?(required_permission(request)) &&
      user.admin_module_allowed?("system")
  rescue StandardError
    false
  end

  def self.required_permission(request)
    if READ_ONLY_METHODS.include?(request.request_method.to_s.upcase)
      "system.jobs.read"
    else
      "system.jobs.manage"
    end
  end
  private_class_method :required_permission
end

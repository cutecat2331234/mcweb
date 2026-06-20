# frozen_string_literal: true

class SidekiqWebConstraint
  SESSION_COOKIE = :session_token

  def self.matches?(request)
    token = request.cookie_jar.signed[SESSION_COOKIE].presence || request.session[SESSION_COOKIE].presence
    return false if token.blank?

    record = Session.find_by(token_digest: Session.digest_token(token))
    return false unless record&.active?

    user = record.user
    return false if user.deleted? || user.banned?

    user.can_access_admin? &&
      user.permission?("admin.access") &&
      user.permission?("system.jobs.read") &&
      user.admin_module_allowed?("system")
  rescue StandardError
    false
  end
end

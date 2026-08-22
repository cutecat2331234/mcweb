# frozen_string_literal: true

module Authentication
  extend ActiveSupport::Concern
  include SafeRedirect

  SESSION_COOKIE = :session_token

  included do
    prepend_before_action :apply_developer_mode_auto_login
    helper_method :current_user, :current_session, :logged_in?, :user_signed_in?
  end

  private

  def apply_developer_mode_auto_login
    identifier = Mcweb::DeveloperMode.auto_login_user
    return if identifier.blank?
    return unless request.get? && request.format.html?
    return if developer_mode_auto_login_excluded_request?
    return if current_session

    user = developer_mode_auto_login_user(identifier)
    return unless user&.session_eligible?

    result = Identity::SessionManager.call(
      user: user,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      remember_me: false,
      authentication_context: Identity::SessionManager::DEVELOPER_MODE_CONTEXT
    )
    return unless result.success?

    reset_session
    @session_record = result.value.fetch(:session)
    @current_user = user
    sign_in(
      session_record: @session_record,
      token: result.value.fetch(:token)
    )
  end

  def developer_mode_auto_login_excluded_request?
    request.path == "/up" ||
      request.path.start_with?("/health/", "/api/")
  end

  def developer_mode_auto_login_user(identifier)
    value = identifier.to_s.strip
    user = User.find_by(id: value.to_i) if value.match?(/\A[1-9]\d*\z/)
    return user if user

    normalized = value.downcase
    User.where(
      "LOWER(email) = :normalized OR LOWER(username) = :normalized OR public_id = :public_id",
      normalized: normalized,
      public_id: value
    ).first
  end

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = current_session&.user
  end

  def current_session
    return @session_record if defined?(@session_record)

    token = cookies.signed[SESSION_COOKIE].presence || session[SESSION_COOKIE].presence
    return @session_record = nil if token.blank?

    record = Session.find_by(token_digest: Session.digest_token(token))
    if record&.developer_mode? && !Mcweb::DeveloperMode.enabled?
      record.revoke! unless record.revoked?
      clear_invalid_session_token
      @session_record = nil
      return
    end

    unless record&.active?
      @session_record = nil
      return
    end

    user = record.user
    unless user.session_eligible?
      record.revoke!
      @session_record = nil
      return
    end

    @session_record = record.tap(&:touch_activity!)
  end

  def clear_invalid_session_token
    request.session.delete(SESSION_COOKIE)
    cookies.delete(SESSION_COOKIE)
  end

  def logged_in?
    current_user.present?
  end

  alias_method :user_signed_in?, :logged_in?

  def require_login
    return if logged_in?

    store_return_location
    redirect_to identity_sign_in_path, alert: t("mcweb.flash.sign_in_required")
  end

  def require_totp_setup
    return unless logged_in?
    return if Mcweb::DeveloperMode.allow?(:skip_two_factor)
    return if current_user.totp_enabled?
    return unless current_user.require_totp?

    return if controller_path.start_with?("identity/security", "identity/sessions", "identity/email_verification", "identity/email_verification_resends")

    redirect_to identity_security_path, alert: t("mcweb.flash.totp_setup_required")
  end

  alias_method :authenticate_user!, :require_login

  def require_permission(key)
    require_login
    return if performed?

    result = Identity::PermissionChecker.call(user: current_user, permission_key: key)
    allowed = result.success? && result.value[:allowed]
    return if allowed

    redirect_to root_path, alert: t("mcweb.flash.permission_denied")
  end

  def sign_in(session_record:, token:, remember_me: false)
    cookie_options = {
      value: token,
      httponly: true,
      secure: secure_session_cookies?,
      same_site: :lax,
      expires: session_record.expires_at
    }

    if remember_me
      cookies.signed.permanent[SESSION_COOKIE] = cookie_options
    else
      cookies.signed[SESSION_COOKIE] = cookie_options
      request.session[SESSION_COOKIE] = token
    end
  end

  def replace_sign_in_token(session_record:, token:)
    clear_invalid_session_token
    @session_record = session_record
    @current_user = session_record.user
    sign_in(
      session_record: session_record,
      token: token,
      remember_me: session_record.remember_me?
    )
  end

  def sign_out
    current_session&.revoke!
    reset_session
    cookies.delete(SESSION_COOKIE)
    @current_user = nil
    @session_record = nil
  end

  alias_method :sign_out_user, :sign_out

  def redirect_after_sign_out(notice: nil)
    flash[:notice] = notice if notice.present?

    if request.inertia?
      inertia_location(signed_out_landing_path)
    else
      redirect_to signed_out_landing_path, status: :see_other
    end
  end

  def store_return_location
    return unless request.get? && !request.xhr?

    path = safe_local_redirect_path(request.fullpath, fallback: nil)
    session[:return_to] = path if path.present?
  end

  def secure_session_cookies?
    return false if Mcweb::DeveloperMode.allow?(:allow_insecure_cookies)
    return false unless Rails.env.production?

    request.get_header("HTTP_X_FORWARDED_PROTO") == "https" || request.ssl?
  end

  def redirect_after_login(default: root_path, notice: nil)
    stored = session.delete(:return_to)
    destination = safe_local_redirect_path(stored, fallback: default)

    # The public portal and admin are separate Inertia applications with
    # different component resolvers and style bundles. An Inertia redirect
    # from the portal login form to an admin page would otherwise ask the
    # portal resolver to load an Admin/* component.
    if request.inertia? && destination.start_with?("/admin")
      flash[:notice] = notice if notice.present?
      inertia_location(destination)
      return
    end

    redirect_to destination, notice: notice
  end
end

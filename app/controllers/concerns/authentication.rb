# frozen_string_literal: true

module Authentication
  extend ActiveSupport::Concern
  include SafeRedirect

  SESSION_COOKIE = :session_token

  included do
    helper_method :current_user, :current_session, :logged_in?, :user_signed_in?
  end

  private

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = current_session&.user
  end

  def current_session
    return @session_record if defined?(@session_record)

    token = cookies.signed[SESSION_COOKIE].presence || session[SESSION_COOKIE].presence
    return @session_record = nil if token.blank?

    record = Session.find_by(token_digest: Session.digest_token(token))
    unless record&.active?
      @session_record = nil
      return
    end

    user = record.user
    if user.deleted? || user.banned?
      record.revoke!
      @session_record = nil
      return
    end

    @session_record = record.tap(&:touch_activity!)
  end

  def logged_in?
    current_user.present?
  end

  alias_method :user_signed_in?, :logged_in?

  def require_login
    return if logged_in?

    store_return_location
    redirect_to identity_sign_in_path, alert: "请先登录后再继续。"
  end

  alias_method :authenticate_user!, :require_login

  def require_permission(key)
    require_login
    return if performed?

    result = Identity::PermissionChecker.call(user: current_user, permission_key: key)
    allowed = result.success? && result.value[:allowed]
    return if allowed

    redirect_to root_path, alert: "你没有权限执行此操作。"
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

  def sign_out
    current_session&.revoke!
    reset_session
    cookies.delete(SESSION_COOKIE)
    @current_user = nil
    @session_record = nil
  end

  alias_method :sign_out_user, :sign_out

  def store_return_location
    return unless request.get? && !request.xhr?

    path = safe_local_redirect_path(request.fullpath, fallback: nil)
    session[:return_to] = path if path.present?
  end

  def secure_session_cookies?
    return false unless Rails.env.production?

    request.get_header("HTTP_X_FORWARDED_PROTO") == "https" || request.ssl?
  end

  def redirect_after_login(default: root_path, notice: nil)
    stored = session.delete(:return_to)
    destination = safe_local_redirect_path(stored, fallback: default)
    redirect_to destination, notice: notice
  end
end

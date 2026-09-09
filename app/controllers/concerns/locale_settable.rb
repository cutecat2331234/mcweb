# frozen_string_literal: true

module LocaleSettable
  extend ActiveSupport::Concern

  LOCALE_COOKIE = "mcweb_locale"
  LOCALE_EXPLICIT_COOKIE = "mcweb_locale_explicit"
  LOCALE_EXPLICIT_SESSION_KEY = :mcweb_locale_explicit
  LOCALE_COOKIE_TTL = 1.year

  included do
    around_action :with_locale
  end

  private

  def with_locale(&block)
    locale = resolved_locale
    mark_locale_bridge_explicit!(locale) if request_locale_explicit?
    synchronize_locale_bridge(locale)
    I18n.with_locale(locale, &block)
  end

  def resolved_locale
    explicit_locale_param ||
      inertia_locale_header ||
      locale_bridge ||
      account_locale ||
      accept_language_locale ||
      I18n.default_locale
  end

  def locale_bridge
    session_locale = normalize_locale(session[:locale])
    cookie_locale = normalize_locale(cookies[LOCALE_COOKIE])
    # Static same-origin renderers can deliberately replace a stale session by
    # setting both shared cookies. An implicit cookie remains a fallback so an
    # unexplained client value cannot silently outrank established session state.
    return cookie_locale if cookie_locale && locale_bridge_explicit?(cookie_locale)
    return session_locale if session_locale
    return nil if respond_to?(:logged_in?, true) && logged_in?

    cookie_locale
  end

  def account_locale
    return unless respond_to?(:logged_in?, true) && logged_in?

    normalize_locale(current_user&.locale)
  end

  def synchronize_locale_bridge(locale)
    normalized = normalize_locale(locale)
    return unless normalized

    session[:locale] = normalized unless session[:locale].to_s == normalized.to_s
    if cookies[LOCALE_COOKIE].to_s != normalized.to_s
      write_locale_cookie(LOCALE_COOKIE, normalized)
    end
  end

  def adopt_account_locale_after_sign_in!(user)
    bridge_locale = normalize_locale(session[:locale]) || normalize_locale(cookies[LOCALE_COOKIE])
    return bridge_locale if bridge_locale && locale_bridge_explicit?(bridge_locale)

    normalized = normalize_locale(user&.locale)
    return unless normalized

    session[:locale] = normalized
    write_locale_cookie(LOCALE_COOKIE, normalized)
    normalized
  end

  def request_locale_explicit?
    # The frontend sends X-McWeb-Locale on every Inertia request, so the
    # header alone does not prove that the visitor deliberately chose it.
    # LocaleController#update records switcher choices through
    # persist_locale_preference! below.
    explicit_locale_param.present?
  end

  def locale_bridge_explicit?(locale)
    normalized = normalize_locale(locale)
    return false unless normalized

    session_marker = session[LOCALE_EXPLICIT_SESSION_KEY]
    session_explicit_locale = if session_marker == true
      # Backward-compatible only while the legacy marker is still bound to the
      # same server-side locale. It cannot promote a later cookie rewrite.
      normalize_locale(session[:locale])
    else
      normalize_locale(session_marker)
    end
    cookie_explicit_locale = normalize_locale(cookies[LOCALE_EXPLICIT_COOKIE])
    session_locale = normalize_locale(session[:locale])
    (session_explicit_locale == normalized && session_locale == normalized) ||
      cookie_explicit_locale == normalized
  end

  def mark_locale_bridge_explicit!(locale)
    normalized = normalize_locale(locale)
    return unless normalized

    session[LOCALE_EXPLICIT_SESSION_KEY] = normalized
    write_locale_cookie(LOCALE_EXPLICIT_COOKIE, normalized)
  end

  def write_locale_cookie(name, value)
    return if cookies[name].to_s == value.to_s

    cookies[name] = {
      value: value,
      expires: LOCALE_COOKIE_TTL.from_now,
      path: "/",
      secure: Rails.env.production? &&
        !Mcweb::DeveloperMode.allow?(:allow_insecure_cookies),
      same_site: :lax,
      httponly: false
    }
  end

  def persist_locale_preference!(locale)
    normalized = normalize_locale(locale)
    return unless normalized

    mark_locale_bridge_explicit!(normalized)
    session[:locale] = normalized
    current_user.update!(locale: normalized) if logged_in? && current_user.locale != normalized.to_s
    synchronize_locale_bridge(normalized)
    normalized
  end

  def explicit_locale_param
    return unless params[:locale].present?

    normalize_locale(params[:locale])
  end

  def inertia_locale_header
    return unless request.headers["X-Inertia"].to_s.casecmp?("true")

    normalize_locale(request.headers["X-McWeb-Locale"])
  end

  def accept_language_locale
    header = request.env["HTTP_ACCEPT_LANGUAGE"].to_s
    return nil if header.blank?

    header.split(",").each do |part|
      tag = part.split(";").first.to_s.strip
      normalized = normalize_locale(tag)
      return normalized if normalized
    end
    nil
  end

  def normalize_locale(value)
    Mcweb::LocaleResolver.normalize(value)
  end
end

# frozen_string_literal: true

module LocaleSettable
  extend ActiveSupport::Concern

  LOCALE_COOKIE = "mcweb_locale"
  LOCALE_COOKIE_TTL = 1.year

  included do
    around_action :with_locale
  end

  private

  def with_locale(&block)
    locale = resolved_locale
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
    normalize_locale(session[:locale]) || normalize_locale(cookies[LOCALE_COOKIE])
  end

  def account_locale
    return unless respond_to?(:logged_in?, true) && logged_in?

    normalize_locale(current_user&.locale)
  end

  def synchronize_locale_bridge(locale)
    normalized = normalize_locale(locale)
    return unless normalized

    session[:locale] = normalized unless session[:locale].to_s == normalized.to_s
    return if cookies[LOCALE_COOKIE].to_s == normalized.to_s

    cookies[LOCALE_COOKIE] = {
      value: normalized,
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

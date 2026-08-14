# frozen_string_literal: true

require "uri"

class LocaleController < ApplicationController
  def update
    locale = normalize_locale(params[:locale])
    unless available_locale?(locale)
      redirect_back fallback_location: root_path, alert: t("mcweb.flash.invalid_locale")
      return
    end

    session[:locale] = locale
    current_user&.update!(locale: locale) if logged_in?

    redirect_to locale_redirect_path, notice: t("mcweb.flash.locale_updated")
  end

  private

  def available_locale?(locale)
    locale.present? && Mcweb::LocaleResolver.available_locales.include?(locale)
  end

  def normalize_locale(value)
    Mcweb::LocaleResolver.normalize(value)
  end

  def locale_redirect_path
    destination = safe_referer_path(fallback: root_path)
    uri = URI.parse(destination)
    query = URI.decode_www_form(uri.query.to_s)
      .reject { |key, _value| key == "locale" }
    uri.query = query.any? ? URI.encode_www_form(query) : nil
    uri.to_s
  rescue URI::InvalidURIError, ArgumentError
    root_path
  end
end

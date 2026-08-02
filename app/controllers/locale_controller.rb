# frozen_string_literal: true

class LocaleController < ApplicationController
  def update
    locale = normalize_locale(params[:locale])
    unless available_locale?(locale)
      redirect_back fallback_location: root_path, alert: t("mcweb.flash.invalid_locale")
      return
    end

    session[:locale] = locale
    current_user&.update!(locale: locale) if logged_in?

    redirect_back fallback_location: root_path, notice: t("mcweb.flash.locale_updated")
  end

  private

  def available_locale?(locale)
    locale.present? && Mcweb::LocaleResolver.available_locales.include?(locale)
  end

  def normalize_locale(value)
    Mcweb::LocaleResolver.normalize(value)
  end
end

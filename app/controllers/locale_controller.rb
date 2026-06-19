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
    locale.present? && I18n.available_locales.map(&:to_s).include?(locale)
  end

  def normalize_locale(value)
    return nil if value.blank?

    string = value.to_s.tr("_", "-")
    case string.downcase
    when "zh", "zh-cn", "zh-hans" then "zh-CN"
    when "en", "en-us", "en-gb" then "en"
    else
      I18n.available_locales.map(&:to_s).find { |loc| loc.casecmp?(string) }
    end
  end
end

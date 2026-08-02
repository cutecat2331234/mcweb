# frozen_string_literal: true

module LocaleSettable
  extend ActiveSupport::Concern

  included do
    around_action :with_locale
  end

  private

  def with_locale(&block)
    I18n.with_locale(resolved_locale, &block)
  end

  def resolved_locale
    candidate = explicit_locale_param || session[:locale].presence
    candidate ||= current_user&.locale if respond_to?(:logged_in?, true) && logged_in?
    candidate ||= accept_language_locale
    normalize_locale(candidate) || I18n.default_locale
  end

  def explicit_locale_param
    return unless params[:locale].present?

    normalize_locale(params[:locale])
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

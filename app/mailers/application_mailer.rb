# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: "from@example.com"
  layout "mailer"
  helper ApplicationHelper
  helper Rails.application.routes.url_helpers

  around_action :with_recipient_locale

  private

  def with_recipient_locale(&block)
    locale = mailer_recipient_locale
    locale.present? ? I18n.with_locale(locale, &block) : yield
  end

  def mailer_recipient_locale
    return @user.locale if defined?(@user) && @user.respond_to?(:locale) && @user.locale.present?

    nil
  end
end

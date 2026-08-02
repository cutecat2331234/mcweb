# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MCWEB_MAIL_FROM", "from@example.com")
  layout "mailer"
  helper ApplicationHelper
  helper Rails.application.routes.url_helpers

  private

  # Mailer actions assign their recipient records before calling +mail+.
  # Resolving the locale in an around_action happens too early because those
  # instance variables do not exist yet, so both the subject and templates
  # would otherwise be rendered with the process-wide default locale.
  def mail(headers = {}, &block)
    with_recipient_locale do
      super(headers, &block)
    end
  end

  def with_recipient_locale(&block)
    I18n.with_locale(mailer_recipient_locale, &block)
  end

  def recipient_t(key, **options)
    I18n.t(key, **options, locale: mailer_recipient_locale)
  end

  def recipient_l(object, **options)
    I18n.l(object, **options, locale: mailer_recipient_locale)
  end

  def mailer_recipient_locale
    explicit_locale = @recipient_locale if defined?(@recipient_locale)
    Mcweb::LocaleResolver.resolve(explicit_locale || mailer_recipient_user&.locale)
  end

  def mailer_recipient_user
    candidates = []
    candidates << @user if defined?(@user)
    candidates << @order.user if defined?(@order) && @order.respond_to?(:user)
    candidates << @refund.order.user if defined?(@refund) && @refund.respond_to?(:order)
    candidates << @cart.user if defined?(@cart) && @cart.respond_to?(:user)
    candidates << @alert.user if defined?(@alert) && @alert.respond_to?(:user)
    candidates << @review.user if defined?(@review) && @review.respond_to?(:user)
    if defined?(@card) && @card.present?
      candidates << @card.owner_user if @card.respond_to?(:owner_user)
      candidates << @card.source_order_item&.order&.user if @card.respond_to?(:source_order_item)
    end

    candidates.compact.find { |candidate| candidate.respond_to?(:locale) }
  end
end

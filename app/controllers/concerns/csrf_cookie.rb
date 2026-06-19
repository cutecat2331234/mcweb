# frozen_string_literal: true

module CsrfCookie
  extend ActiveSupport::Concern

  included do
    after_action :set_csrf_cookie
  end

  private

  def set_csrf_cookie
    return unless protect_against_forgery?

    cookies["XSRF-TOKEN"] = {
      value: form_authenticity_token,
      secure: Rails.env.production?,
      same_site: :lax
    }
  end
end

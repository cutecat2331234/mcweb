# frozen_string_literal: true

module Identity
  class EmailVerificationsController < ApplicationController
    def show
      result = Identity::VerifyEmail.call(token: params[:token], ip_address: request.remote_ip)

      if result.success?
        redirect_to identity_sign_in_path, notice: t("mcweb.flash.email_verified")
      else
        redirect_to root_path, alert: service_error_message(result)
      end
    end
  end
end

# frozen_string_literal: true

module Identity
  class EmailVerificationsController < ApplicationController
    skip_installation_guard only: :show

    def show
      result = Identity::VerifyEmail.call(token: params[:token])

      if result.success?
        redirect_to identity_sign_in_path, notice: "Email verified successfully. You can now sign in."
      else
        redirect_to root_path, alert: service_error_message(result)
      end
    end
  end
end

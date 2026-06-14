# frozen_string_literal: true

module Identity
  class PasswordResetsController < ApplicationController
    skip_installation_guard
    before_action :redirect_if_logged_in, only: %i[new create]

    def new
    end

    def create
      result = Identity::ResetPassword.call(email: password_reset_params[:email])

      if result.success?
        redirect_to identity_sign_in_path, notice: "If the email exists, a reset link has been sent."
      else
        flash.now[:alert] = service_error_message(result)
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      result = Identity::ResetPassword.call(
        token: params[:token],
        new_password: password_reset_params[:password]
      )

      if result.success?
        redirect_to identity_sign_in_path, notice: "Password has been reset. You can now sign in."
      else
        flash.now[:alert] = service_error_message(result)
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def password_reset_params
      params.expect(password_reset: %i[email password password_confirmation])[:password_reset]
    end

    def redirect_if_logged_in
      redirect_to root_path if logged_in?
    end
  end
end

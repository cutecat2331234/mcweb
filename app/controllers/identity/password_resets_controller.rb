# frozen_string_literal: true

module Identity
  class PasswordResetsController < ApplicationController
    skip_installation_guard
    before_action :redirect_if_logged_in, only: %i[new create]

    def new
      render inertia: "Identity/PasswordResets/New"
    end

    def create
      result = Identity::ResetPassword.call(email: password_reset_params[:email])

      if result.success?
        redirect_to identity_sign_in_path, notice: "If the email exists, a reset link has been sent."
      else
        render inertia: "Identity/PasswordResets/New",
               status: :unprocessable_entity,
               errors: { base: service_error_message(result) }
      end
    end

    def edit
      render inertia: "Identity/PasswordResets/Edit", props: { token: params[:token] }
    end

    def update
      result = Identity::ResetPassword.call(
        token: params[:token],
        new_password: password_reset_params[:password]
      )

      if result.success?
        redirect_to identity_sign_in_path, notice: "Password has been reset. You can now sign in."
      else
        render inertia: "Identity/PasswordResets/Edit",
               props: { token: params[:token] },
               status: :unprocessable_entity,
               errors: { base: service_error_message(result) }
      end
    end

    private

    def password_reset_params
      params.require(:password_reset).permit(:email, :password, :password_confirmation)
    end

    def redirect_if_logged_in
      redirect_to root_path if logged_in?
    end
  end
end

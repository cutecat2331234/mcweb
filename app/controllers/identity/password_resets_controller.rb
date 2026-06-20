# frozen_string_literal: true

module Identity
  class PasswordResetsController < ApplicationController
    before_action :redirect_if_logged_in, only: %i[new create]

    def new
      render inertia: "Identity/PasswordResets/New"
    end

    def create
      result = Identity::ResetPassword.call(
        email: password_reset_params[:email],
        ip_address: request.remote_ip
      )

      if result.success?
        redirect_to identity_sign_in_path, notice: t("mcweb.flash.password_reset_sent")
      else
        render inertia: "Identity/PasswordResets/New",
               status: :unprocessable_entity,
               props: { form_error: service_error_message(result) }
      end
    end

    def edit
      render inertia: "Identity/PasswordResets/Edit", props: { token: params[:token] }
    end

    def update
      p = password_reset_params
      if p[:password].present? && p[:password] != p[:password_confirmation]
        return render inertia: "Identity/PasswordResets/Edit",
                      props: { token: params[:token], form_errors: { base: "两次输入的密码不一致。" } },
                      status: :unprocessable_entity
      end

      result = Identity::ResetPassword.call(
        token: params[:token],
        new_password: p[:password],
        ip_address: request.remote_ip
      )

      if result.success?
        redirect_to identity_sign_in_path, notice: t("mcweb.flash.password_reset_success")
      else
        render inertia: "Identity/PasswordResets/Edit",
               props: { token: params[:token], form_errors: inertia_form_errors(result) },
               status: :unprocessable_entity
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

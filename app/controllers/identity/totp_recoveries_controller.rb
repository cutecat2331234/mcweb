# frozen_string_literal: true

module Identity
  class TotpRecoveriesController < ApplicationController
    def new
      render inertia: "Identity/TotpRecoveries/New"
    end

    def create
      Identity::RecoverTotp.call(
        email: recovery_params[:email],
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      redirect_to identity_sign_in_path, notice: t("mcweb.flash.totp_recovery_email_sent")
    end

    def edit
      render inertia: "Identity/TotpRecoveries/Edit", props: { token: params[:token] }
    end

    def update
      result = Identity::RecoverTotp.call(
        token: params[:token],
        password: recovery_params[:password],
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      if result.success?
        redirect_to identity_sign_in_path, notice: t("mcweb.flash.totp_recovery_completed")
      else
        render inertia: "Identity/TotpRecoveries/Edit",
               props: {
                 token: params[:token],
                 form_errors: inertia_form_errors(result)
               },
               status: service_error_status(result)
      end
    end

    private

    def recovery_params
      params.require(:totp_recovery).permit(:email, :password)
    end
  end
end

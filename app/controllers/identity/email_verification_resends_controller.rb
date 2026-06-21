# frozen_string_literal: true

module Identity
  class EmailVerificationResendsController < ApplicationController
    def new
      render inertia: "Identity/EmailVerificationResends/New", props: {
        email: params[:email].to_s
      }
    end

    def create
      Identity::ResendEmailVerification.call(
        email: resend_params[:email],
        ip_address: request.remote_ip
      )

      redirect_to identity_sign_in_path, notice: t("mcweb.flash.verification_email_resent")
    end

    private

    def resend_params
      params.expect(resend: [ :email ])[:resend]
    end
  end
end

# frozen_string_literal: true

module Identity
  class SessionsController < ApplicationController
    skip_installation_guard only: %i[new create destroy]

    before_action :redirect_if_signed_in, only: %i[new create]

    def new
      render inertia: "Identity/Sessions/New"
    end

    def create
      result = Identity::AuthenticateUser.call(
        email: session_params[:email],
        password: session_params[:password],
        totp_code: session_params[:totp_code],
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        remember_me: session_params[:remember_me] == "1" || session_params[:remember_me] == true
      )

      if result.success?
        sign_in(
          session_record: result.value[:session],
          token: result.value[:token],
          remember_me: session_params[:remember_me] == "1" || session_params[:remember_me] == true
        )
        redirect_after_login notice: "Signed in successfully."
      else
        render inertia: "Identity/Sessions/New",
               status: :unprocessable_entity,
               errors: { base: service_error_message(result) }
      end
    end

    def destroy
      sign_out
      redirect_to root_path, notice: "Signed out."
    end

    private

    def session_params
      params.require(:session).permit(:email, :password, :totp_code, :remember_me)
    end

    def redirect_if_signed_in
      redirect_to root_path if user_signed_in?
    end
  end
end

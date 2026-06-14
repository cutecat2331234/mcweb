# frozen_string_literal: true

module Identity
  class SessionsController < ApplicationController
    skip_installation_guard only: %i[new create destroy]

    before_action :redirect_if_signed_in, only: %i[new create]

    def new
    end

    def create
      result = Identity::AuthenticateUser.call(
        email: session_params[:email],
        password: session_params[:password],
        totp_code: session_params[:totp_code],
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        remember_me: session_params[:remember_me] == "1"
      )

      if result.success?
        sign_in(
          session: result.value[:session],
          token: result.value[:token],
          remember_me: session_params[:remember_me] == "1"
        )
        redirect_after_login notice: "Signed in successfully."
      else
        flash.now[:alert] = service_error_message(result)
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      sign_out
      redirect_to root_path, notice: "Signed out."
    end

    private

    def session_params
      params.expect(session: %i[email password totp_code remember_me])[:session]
    end

    def redirect_if_signed_in
      redirect_to root_path if user_signed_in?
    end
  end
end

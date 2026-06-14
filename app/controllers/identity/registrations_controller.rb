# frozen_string_literal: true

module Identity
  class RegistrationsController < ApplicationController
    skip_installation_guard only: %i[new create]

    before_action :redirect_if_signed_in, only: %i[new create]

    def new
    end

    def create
      result = Identity::RegisterUser.call(
        email: registration_params[:email],
        username: registration_params[:username],
        password: registration_params[:password],
        display_name: registration_params[:display_name],
        locale: registration_params[:locale],
        time_zone: registration_params[:time_zone]
      )

      if result.success?
        redirect_to identity_sign_in_path, notice: "Account created. Please check your email to verify your address."
      else
        flash.now[:alert] = service_error_message(result)
        render :new, status: :unprocessable_entity
      end
    end

    private

    def registration_params
      params.expect(registration: %i[email username password display_name locale time_zone])[:registration]
    end

    def redirect_if_signed_in
      redirect_to root_path if user_signed_in?
    end
  end
end

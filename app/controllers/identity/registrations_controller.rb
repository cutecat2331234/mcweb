# frozen_string_literal: true

module Identity
  class RegistrationsController < ApplicationController
    skip_installation_guard only: %i[new create]

    before_action :redirect_if_signed_in, only: %i[new create]

    def new
      render inertia: "Identity/Registrations/New"
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
        render inertia: "Identity/Registrations/New",
               status: :unprocessable_entity,
               errors: { base: service_error_message(result) }
      end
    end

    private

    def registration_params
      params.require(:registration).permit(:email, :username, :password, :display_name, :locale, :time_zone)
    end

    def redirect_if_signed_in
      redirect_to root_path if user_signed_in?
    end
  end
end

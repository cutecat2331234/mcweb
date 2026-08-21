# frozen_string_literal: true

module Identity
  class ProfilesController < ApplicationController
    before_action :require_login
    after_action :set_private_no_store

    def show
      render_profile
    end

    def update
      result = Identity::UpdateProfile.call(
        actor: current_user,
        user: current_user,
        attributes: profile_params,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      unless result.success?
        return render_profile(
          values: profile_params.to_h,
          form_errors: inertia_form_errors(result, prefix: "profile"),
          status: :unprocessable_entity
        )
      end

      updated_user = result.value.fetch(:user)
      session[:locale] = updated_user.locale
      redirect_to identity_profile_path,
                  notice: I18n.t("mcweb.flash.profile_updated", locale: updated_user.locale)
    end

    private

    def render_profile(values: nil, form_errors: nil, status: :ok)
      values = values&.symbolize_keys || {
        display_name: current_user.display_name,
        locale: current_user.locale
      }

      render inertia: "Identity/Profiles/Show", props: {
        profile: {
          username: current_user.username,
          email: current_user.email,
          display_name: values[:display_name],
          locale: values[:locale]
        },
        form_errors: form_errors
      }, status: status
    end

    def profile_params
      params.expect(profile: %i[display_name locale])
    end

    def set_private_no_store
      response.set_header("Cache-Control", "private, no-store")
    end
  end
end

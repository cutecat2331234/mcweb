# frozen_string_literal: true

module Identity
  class PasswordsController < ApplicationController
    before_action :require_login
    after_action :set_private_no_store

    def edit
      render_password_form
    end

    def update
      result = Identity::ChangePassword.call(
        user: current_user,
        current_password: password_params[:current_password],
        new_password: password_params[:new_password],
        new_password_confirmation: password_params[:new_password_confirmation],
        code: password_params[:code],
        current_session: current_session,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      unless result.success?
        apply_retry_after_header(result)
        return render_password_form(
          form_errors: inertia_form_errors(result, prefix: "password_change"),
          status: service_error_status(result)
        )
      end

      redirect_to identity_security_password_path,
                  notice: t("mcweb.flash.password_changed")
    end

    private

    def render_password_form(form_errors: nil, status: :ok)
      render inertia: "Identity/Passwords/Edit", props: {
        totp_enabled: current_user.totp_enabled?,
        form_errors: form_errors
      }, status: status
    end

    def password_params
      params.expect(
        password_change: %i[
          current_password
          new_password
          new_password_confirmation
          code
        ]
      )
    end

    def set_private_no_store
      response.set_header("Cache-Control", "private, no-store")
    end
  end
end

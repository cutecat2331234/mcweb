# frozen_string_literal: true

module Identity
  class EmailChangesController < ApplicationController
    def confirm
      result = ConfirmEmailChange.call(
        token: params[:token],
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      if result.success?
        user = result.value.fetch(:user)
        destination = current_user&.id == user.id ? identity_security_path : identity_sign_in_path
        redirect_to destination, notice: t("mcweb.flash.email_change_confirmed")
      else
        redirect_to signed_out_landing_path, alert: service_error_message(result)
      end
    end

    def revoke
      result = RevokeEmailChange.call(
        token: params[:token],
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      unless result.success?
        return redirect_to signed_out_landing_path, alert: service_error_message(result)
      end

      sign_out if result.value.fetch(:reverted) && current_user&.id == result.value.fetch(:user).id
      flash_key = result.value.fetch(:reverted) ? :email_change_reverted : :email_change_cancelled
      redirect_to signed_out_landing_path, notice: t("mcweb.flash.#{flash_key}")
    end
  end
end

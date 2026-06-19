# frozen_string_literal: true

module Identity
  class EmailVerificationsController < ApplicationController
    def show
      result = Identity::VerifyEmail.call(token: params[:token])

      if result.success?
        redirect_to identity_sign_in_path, notice: "邮箱已验证，现在可以登录了。"
      else
        redirect_to root_path, alert: service_error_message(result)
      end
    end
  end
end

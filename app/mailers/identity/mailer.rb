# frozen_string_literal: true

module Identity
  class Mailer < ApplicationMailer
    def verification_email(user_id, token)
      @user = User.find(user_id)
      @verification_url = identity_email_verification_url(token: token)

      mail(to: @user.email, subject: "请验证您的 McWeb 邮箱")
    end

    def password_reset_email(user_id, token)
      @user = User.find(user_id)
      @reset_url = edit_identity_password_reset_url(token: token)

      mail(to: @user.email, subject: "McWeb 密码重置")
    end
  end
end

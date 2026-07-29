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

    def totp_recovery_email(user_id, token)
      @user = User.find(user_id)
      @recovery_url = edit_identity_totp_recovery_url(token: token)

      I18n.with_locale(@user.locale) do
        mail(
          to: @user.email,
          subject: I18n.t("mcweb.mail.totp_recovery.subject")
        )
      end
    end
  end
end

# frozen_string_literal: true

module Identity
  class Mailer < ApplicationMailer
    def verification_email(user_id, token)
      @user = User.find(user_id)
      @verification_url = identity_email_verification_url(token: token)

      mail(to: @user.email, subject: recipient_t("mcweb.mail.identity.subjects.verification"))
    end

    def password_reset_email(user_id, token)
      @user = User.find(user_id)
      @reset_url = edit_identity_password_reset_url(token: token)

      mail(to: @user.email, subject: recipient_t("mcweb.mail.identity.subjects.password_reset"))
    end

    def totp_recovery_email(user_id, token)
      @user = User.find(user_id)
      @recovery_url = edit_identity_totp_recovery_url(token: token)

      mail(
        to: @user.email,
        subject: recipient_t("mcweb.mail.identity.subjects.totp_recovery")
      )
    end
  end
end

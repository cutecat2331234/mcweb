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

    def password_changed_email(user_id, changed_at, revoked_session_count)
      @user = User.find(user_id)
      @changed_at = Time.zone.parse(changed_at.to_s)
      @revoked_session_count = revoked_session_count.to_i
      @security_url = identity_security_url
      @reset_url = identity_password_resets_landing_url

      mail(to: @user.email, subject: recipient_t("mcweb.mail.identity.subjects.password_changed"))
    end

    def totp_enabled_email(user_id, enabled_at, revoked_session_count)
      @user = User.find(user_id)
      @enabled_at = Time.zone.parse(enabled_at.to_s)
      @revoked_session_count = revoked_session_count.to_i
      @security_url = identity_security_url
      @recovery_url = new_identity_totp_recovery_url
      @reset_url = identity_password_resets_landing_url

      mail(to: @user.email, subject: recipient_t("mcweb.mail.identity.subjects.totp_enabled"))
    end

    def totp_recovery_email(user_id, token)
      @user = User.find(user_id)
      @recovery_url = edit_identity_totp_recovery_url(token: token)

      mail(
        to: @user.email,
        subject: recipient_t("mcweb.mail.identity.subjects.totp_recovery")
      )
    end

    def email_change_confirmation(request_id, token)
      @email_change_request = Identity::EmailChangeRequest.find(request_id)
      @user = @email_change_request.user
      @confirmation_url = identity_email_change_confirmation_url(token:)

      mail(
        to: @email_change_request.requested_email,
        subject: recipient_t("mcweb.mail.identity.subjects.email_change_confirmation")
      )
    end

    def email_change_security_notice(request_id, token)
      @email_change_request = Identity::EmailChangeRequest.find(request_id)
      @user = @email_change_request.user
      @revocation_url = identity_email_change_revocation_url(token:)

      mail(
        to: @email_change_request.original_email,
        subject: recipient_t("mcweb.mail.identity.subjects.email_change_security_notice")
      )
    end
  end
end

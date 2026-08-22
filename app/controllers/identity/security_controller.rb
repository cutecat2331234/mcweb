# frozen_string_literal: true

module Identity
  class SecurityController < ApplicationController
    include PrivateNoStoreResponse

    before_action :require_login
    skip_before_action :require_totp_setup, raise: false

    def show
      render inertia: "Identity/Security/Show", props: {
        email: current_user.email,
        email_verified: current_user.email_verified?,
        totp_enabled: current_user.totp_enabled?,
        require_totp: current_user.require_totp?,
        pending_email_change: pending_email_change_props,
        pending_totp: pending_totp_props,
        recovery_codes_remaining: current_user.totp_enabled? ? Array(current_user.recovery_codes).size : 0,
        new_recovery_codes: session.delete(:identity_recovery_codes)
      }
    end

    def setup_totp
      setup_secret = nil
      already_enabled = false
      User.transaction do
        current_user.lock!
        if current_user.totp_enabled?
          already_enabled = true
        else
          current_user.setup_totp!
          setup_secret = current_user.totp_secret
        end
      end
      if already_enabled
        return redirect_to identity_security_path, alert: t("mcweb.flash.totp_already_enabled")
      end

      session[:pending_totp_secret] = setup_secret

      redirect_to identity_security_path, notice: t("mcweb.flash.totp_setup_started")
    end

    def confirm_totp
      secret = session[:pending_totp_secret].presence
      return redirect_to identity_security_path, alert: t("mcweb.flash.totp_setup_missing") if secret.blank?

      confirmation = :invalid
      recovery_codes = nil
      User.transaction do
        current_user.lock!
        if current_user.totp_enabled?
          confirmation = :already_enabled
        elsif !secure_totp_secret_match?(current_user.totp_secret.to_s, secret)
          confirmation = :stale
        elsif User.verify_totp_code(secret, confirm_params[:code])
          current_user.update!(totp_enabled: true)
          Administration::AuditLogger.call(
            actor: current_user,
            action: "identity.totp_enabled",
            resource: current_user,
            metadata: { recovery_code_count: Array(current_user.recovery_codes).size },
            ip_address: request.remote_ip,
            user_agent: request.user_agent
          )
          recovery_codes = Array(current_user.recovery_codes)
          confirmation = :enabled
        end
      end

      case confirmation
      when :enabled
        session.delete(:pending_totp_secret)
        session[:identity_recovery_codes] = recovery_codes
      when :stale
        session.delete(:pending_totp_secret)
        return redirect_to identity_security_path, alert: t("mcweb.flash.totp_setup_stale")
      when :already_enabled
        session.delete(:pending_totp_secret)
        return redirect_to identity_security_path, alert: t("mcweb.flash.totp_already_enabled")
      else
        return redirect_to identity_security_path, alert: t("mcweb.flash.totp_invalid")
      end

      redirect_to identity_security_path, notice: t("mcweb.flash.totp_enabled")
    end

    def disable_totp
      verification = nil
      User.transaction do
        current_user.lock!
        verification = Identity::SensitiveActionVerifier.call(
          user: current_user,
          password: disable_params[:password],
          code: disable_params[:code]
        )
        raise ActiveRecord::Rollback unless verification.success?

        current_user.update!(totp_enabled: false, totp_secret: nil, recovery_codes: nil)
        Administration::AuditLogger.call(
          actor: current_user,
          action: "identity.totp_disabled",
          resource: current_user,
          metadata: { verification_method: verification.value.fetch(:method) },
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )
      end
      unless verification&.success?
        return redirect_to identity_security_path, alert: service_error_message(verification)
      end

      session.delete(:pending_totp_secret)
      session.delete(:identity_recovery_codes)

      redirect_to identity_security_path, notice: t("mcweb.flash.totp_disabled")
    end

    def regenerate_recovery_codes
      result = Identity::RegenerateRecoveryCodes.call(
        user: current_user,
        password: recovery_code_params[:password],
        code: recovery_code_params[:code],
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      if result.success?
        session[:identity_recovery_codes] = result.value.fetch(:codes)
        redirect_to identity_security_path, notice: t("mcweb.flash.totp_recovery_codes_regenerated")
      else
        redirect_to identity_security_path, alert: service_error_message(result)
      end
    end

    def change_email
      result = Identity::ChangeEmail.call(
        user: current_user,
        email: email_params[:email],
        password: email_params[:password],
        code: email_params[:code],
        current_session: current_session,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      if result.success?
        flash_key = result.value.fetch(:verification_required) ? :email_changed_verify : :email_changed
        redirect_to identity_security_path, notice: t("mcweb.flash.#{flash_key}")
      else
        redirect_to identity_security_path, alert: service_error_message(result)
      end
    end

    def close_account
      result = Identity::CloseAccount.call(
        user: current_user,
        password: account_close_params[:password],
        code: account_close_params[:code],
        confirmation: account_close_params[:confirmation],
        closure_mode: account_close_params[:closure_mode].presence || "anonymize",
        reason: account_close_params[:reason],
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      unless result.success?
        return redirect_to identity_security_path, alert: service_error_message(result)
      end

      sign_out
      redirect_after_sign_out(notice: t("mcweb.flash.account_closed"))
    end

    private

    def pending_email_change_props
      request_record = current_user.email_change_requests.active_pending.recent_first.first
      return unless request_record

      {
        email: request_record.requested_email,
        requested_at: request_record.requested_at.iso8601,
        expires_at: request_record.expires_at.iso8601
      }
    end

    def pending_totp_props
      secret = session[:pending_totp_secret].presence
      return nil if secret.blank? || current_user.totp_enabled?
      unless secure_totp_secret_match?(current_user.totp_secret.to_s, secret)
        session.delete(:pending_totp_secret)
        return nil
      end

      totp = ROTP::TOTP.new(secret, issuer: "Mcweb")
      qr = RQRCode::QRCode.new(totp.provisioning_uri(current_user.email))

      {
        secret: secret,
        provisioning_uri: totp.provisioning_uri(current_user.email),
        qr_svg: qr.as_svg(module_size: 4, standalone: true)
      }
    end

    def secure_totp_secret_match?(stored_secret, pending_secret)
      stored_secret.bytesize == pending_secret.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(stored_secret, pending_secret)
    end

    def confirm_params
      params.expect(totp: [ :code ])
    end

    def disable_params
      params.expect(totp: %i[password code])
    end

    def recovery_code_params
      params.expect(recovery_codes: %i[password code])
    end

    def email_params
      params.expect(email_change: %i[email password code])
    end

    def account_close_params
      params.expect(account_close: %i[password code confirmation closure_mode reason])
    end
  end
end

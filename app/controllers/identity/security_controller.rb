# frozen_string_literal: true

module Identity
  class SecurityController < ApplicationController
    before_action :require_login
    skip_before_action :require_totp_setup, raise: false

    def show
      render inertia: "Identity/Security/Show", props: {
        email_verified: current_user.email_verified?,
        totp_enabled: current_user.totp_enabled?,
        require_totp: current_user.require_totp?,
        pending_totp: pending_totp_props,
        recovery_codes_remaining: current_user.totp_enabled? ? Array(current_user.recovery_codes).size : 0
      }
    end

    def setup_totp
      return redirect_to identity_security_path, alert: t("mcweb.flash.totp_already_enabled") if current_user.totp_enabled?

      current_user.setup_totp!
      session[:pending_totp_secret] = current_user.totp_secret

      redirect_to identity_security_path, notice: t("mcweb.flash.totp_setup_started")
    end

    def confirm_totp
      secret = session[:pending_totp_secret].presence || current_user.totp_secret
      return redirect_to identity_security_path, alert: t("mcweb.flash.totp_setup_missing") if secret.blank?

      totp = ROTP::TOTP.new(secret, issuer: "Mcweb")
      unless totp.verify(confirm_params[:code].to_s, drift_behind: 30, drift_ahead: 30)
        return redirect_to identity_security_path, alert: t("mcweb.flash.totp_invalid")
      end

      current_user.update!(totp_enabled: true)
      session.delete(:pending_totp_secret)

      redirect_to identity_security_path, notice: t("mcweb.flash.totp_enabled")
    end

    def disable_totp
      unless current_user.authenticate(disable_params[:password].to_s)
        return redirect_to identity_security_path, alert: t("mcweb.flash.password_incorrect")
      end

      unless current_user.verify_totp(disable_params[:code].to_s) || current_user.consume_recovery_code!(disable_params[:code].to_s)
        return redirect_to identity_security_path, alert: t("mcweb.flash.totp_invalid")
      end

      current_user.update!(totp_enabled: false, totp_secret: nil, recovery_codes: nil)
      session.delete(:pending_totp_secret)

      redirect_to identity_security_path, notice: t("mcweb.flash.totp_disabled")
    end

    private

    def pending_totp_props
      secret = session[:pending_totp_secret].presence
      return nil if secret.blank? || current_user.totp_enabled?

      totp = ROTP::TOTP.new(secret, issuer: "Mcweb")
      qr = RQRCode::QRCode.new(totp.provisioning_uri(current_user.email))

      {
        secret: secret,
        provisioning_uri: totp.provisioning_uri(current_user.email),
        qr_svg: qr.as_svg(module_size: 4, standalone: true)
      }
    end

    def confirm_params
      params.expect(totp: [ :code ])[:totp]
    end

    def disable_params
      params.expect(totp: %i[password code])[:totp]
    end
  end
end

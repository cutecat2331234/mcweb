# frozen_string_literal: true

module Identity
  class SessionsController < ApplicationController
    include GuestCartMergeable

    PENDING_SECOND_FACTOR_KEY = :identity_pending_second_factor
    SECOND_FACTOR_TTL = 5.minutes

    before_action :redirect_if_signed_in, only: %i[new create show two_factor verify_two_factor]

    def new
      clear_pending_second_factor!
      render inertia: "Identity/Sessions/New"
    end

    def show
      redirect_to identity_sign_in_path
    end

    def create
      clear_pending_second_factor!
      remember_me = remember_me?
      credentials_result = Identity::VerifyCredentials.call(
        email: session_params[:email],
        password: session_params[:password],
        ip_address: request.remote_ip
      )

      unless credentials_result.success?
        return render_sign_in_error(credentials_result)
      end

      user = credentials_result.value.fetch(:user)
      credential_snapshot = credentials_result.value.fetch(:credential_snapshot)
      if credentials_result.value.fetch(:two_factor_required)
        begin_pending_second_factor!(user:, remember_me:, credential_snapshot:)
        return redirect_to identity_session_two_factor_path, status: :see_other
      end

      result = complete_authentication(user:, remember_me:, credential_snapshot:)
      if result.code == "two_factor_code_required"
        begin_pending_second_factor!(user:, remember_me:, credential_snapshot:)
        return redirect_to identity_session_two_factor_path, status: :see_other
      end

      result.success? ? finish_sign_in(result, remember_me:) : render_sign_in_error(result)
    end

    def two_factor
      return redirect_expired_second_factor unless pending_second_factor

      render inertia: "Identity/Sessions/TwoFactor"
    end

    def verify_two_factor
      pending = pending_second_factor
      return redirect_expired_second_factor unless pending

      rate_limit_result = Administration::AbuseRateLimit.call(
        action: :login,
        account: pending.fetch(:user).email,
        ip_address: request.remote_ip
      )
      return render_two_factor_error(rate_limit_result) if rate_limit_result.failure?

      result = complete_authentication(
        user: pending.fetch(:user),
        remember_me: pending.fetch(:remember_me),
        totp_code: two_factor_params[:code],
        two_factor_required: true,
        credential_snapshot: pending.fetch(:credential_snapshot)
      )

      if result.success?
        clear_pending_second_factor!
        finish_sign_in(result, remember_me: pending.fetch(:remember_me))
      else
        render_two_factor_error(result)
      end
    end

    def destroy
      sign_out
      redirect_to root_path, notice: t("mcweb.flash.sign_out_success")
    end

    private

    def session_params
      params.require(:session).permit(:email, :password, :remember_me)
    end

    def two_factor_params
      params.require(:two_factor).permit(:code)
    end

    def remember_me?
      session_params[:remember_me] == "1" || session_params[:remember_me] == true
    end

    def complete_authentication(
      user:,
      remember_me:,
      credential_snapshot:,
      totp_code: nil,
      two_factor_required: false
    )
      Identity::CompleteAuthentication.call(
        user:,
        totp_code:,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        remember_me:,
        two_factor_required:,
        credential_snapshot:
      )
    end

    def finish_sign_in(result, remember_me:)
      sign_in(
        session_record: result.value.fetch(:session),
        token: result.value.fetch(:token),
        remember_me:
      )
      merge_guest_cart!
      redirect_after_login(
        default: FeatureFlags.primary_portal_path(self),
        notice: t("mcweb.flash.sign_in_success")
      )
    end

    def render_sign_in_error(result)
      apply_retry_after_header(result)
      render inertia: "Identity/Sessions/New",
             status: service_error_status(result),
             props: { login_error: service_error_message(result) }
    end

    def render_two_factor_error(result)
      apply_retry_after_header(result)
      render inertia: "Identity/Sessions/TwoFactor",
             status: service_error_status(result),
             props: { verification_error: service_error_message(result) }
    end

    def begin_pending_second_factor!(user:, remember_me:, credential_snapshot:)
      session[PENDING_SECOND_FACTOR_KEY] = {
        "user_id" => user.id,
        "issued_at" => Time.current.to_i,
        "remember_me" => remember_me,
        "credential_snapshot" => credential_snapshot
      }
    end

    def pending_second_factor
      raw = session[PENDING_SECOND_FACTOR_KEY]
      return if raw.blank?

      payload = raw.to_h.with_indifferent_access
      issued_at = Integer(payload[:issued_at], exception: false)
      if issued_at.nil? || Time.at(issued_at) < SECOND_FACTOR_TTL.ago
        clear_pending_second_factor!
        return
      end

      user = User.find_by(id: payload[:user_id])
      credential_snapshot = payload[:credential_snapshot].to_s
      unless user&.totp_enabled? && CredentialSnapshot.valid?(user, credential_snapshot)
        clear_pending_second_factor!
        return
      end

      {
        user:,
        remember_me: ActiveModel::Type::Boolean.new.cast(payload[:remember_me]),
        credential_snapshot:
      }
    end

    def clear_pending_second_factor!
      session.delete(PENDING_SECOND_FACTOR_KEY)
    end

    def redirect_expired_second_factor
      clear_pending_second_factor!
      redirect_to identity_sign_in_path,
                  alert: t("mcweb.flash.two_factor_challenge_expired"),
                  status: :see_other
    end

    def redirect_if_signed_in
      redirect_to FeatureFlags.primary_portal_path(self) if user_signed_in?
    end
  end
end

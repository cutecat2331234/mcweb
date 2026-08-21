# frozen_string_literal: true

module Identity
  class CompleteAuthentication < ApplicationService
    def initialize(
      user:,
      totp_code: nil,
      ip_address: nil,
      user_agent: nil,
      remember_me: false,
      two_factor_required: false,
      credential_snapshot: nil
    )
      @user = user
      @totp_code = totp_code
      @ip_address = ip_address
      @user_agent = user_agent
      @remember_me = remember_me
      @two_factor_required = two_factor_required
      @credential_snapshot = credential_snapshot
    end

    def call
      return generic_failure unless @user&.persisted?

      User.transaction do
        @user.lock!
        return generic_failure unless CredentialSnapshot.valid?(@user, @credential_snapshot)
        return generic_failure unless account_still_eligible?

        if second_factor_required?
          if @totp_code.blank?
            return ServiceResult.failure(
              error: "two_factor_code_required",
              code: "two_factor_code_required"
            )
          end
          unless verify_second_factor
            return ServiceResult.failure(
              error: "invalid_two_factor_code",
              code: "invalid_two_factor_code"
            )
          end
        end

        sign_in_attributes = {
          last_sign_in_at: Time.current,
          last_sign_in_ip: @ip_address
        }
        unless Mcweb::DeveloperMode.allow?(:skip_account_lockout)
          sign_in_attributes[:failed_login_count] = 0
          sign_in_attributes[:locked_until] = nil
        end
        @user.update!(sign_in_attributes)

        session_result = SessionManager.call(
          user: @user,
          ip_address: @ip_address,
          user_agent: @user_agent,
          remember_me: @remember_me,
          credential_snapshot: @credential_snapshot,
          authentication_context: SessionManager::VERIFIED_CREDENTIALS_CONTEXT
        )
        return generic_failure if session_result.failure?

        Administration::AuditLogger.call(
          actor: @user,
          action: "identity.sign_in",
          resource: @user,
          ip_address: @ip_address,
          user_agent: @user_agent
        )

        ServiceResult.success(
          session: session_result.value[:session],
          token: session_result.value[:token]
        )
      end
    end

    private

    def account_still_eligible?
      return false unless @user&.session_eligible?
      return false if @user.developer_mode_relaxed_password? && !Mcweb::DeveloperMode.allow?(:relax_password_policy)

      production_email_verified? || Mcweb::DeveloperMode.allow?(:skip_email_verification)
    end

    def production_email_verified?
      @user.email_verified? && !@user.developer_mode_email_verified?
    end

    def second_factor_required?
      return false if Mcweb::DeveloperMode.allow?(:skip_two_factor)

      @two_factor_required || @user.totp_enabled?
    end

    def verify_second_factor
      return false unless @user.totp_enabled?

      @user.verify_totp(@totp_code) || @user.consume_recovery_code!(@totp_code.to_s)
    end

    def generic_failure
      ServiceResult.failure(
        error: "invalid_email_or_password",
        code: "invalid_email_or_password"
      )
    end
  end
end

# frozen_string_literal: true

module Identity
  class AuthenticateUser < ApplicationService
    def initialize(email:, password:, totp_code: nil, ip_address: nil, user_agent: nil, remember_me: false)
      @email = email.to_s.strip.downcase
      @password = password
      @totp_code = totp_code
      @ip_address = ip_address
      @user_agent = user_agent
      @remember_me = remember_me
    end

    def call
      credentials_result = VerifyCredentials.call(
        email: @email,
        password: @password,
        ip_address: @ip_address
      )
      return credentials_result if credentials_result.failure?

      CompleteAuthentication.call(
        user: credentials_result.value.fetch(:user),
        totp_code: @totp_code,
        ip_address: @ip_address,
        user_agent: @user_agent,
        remember_me: @remember_me,
        two_factor_required: credentials_result.value.fetch(:two_factor_required),
        credential_snapshot: credentials_result.value.fetch(:credential_snapshot)
      )
    end
  end
end

# frozen_string_literal: true

module Identity
  class SensitiveActionVerifier < ApplicationService
    def initialize(user:, password:, code: nil, consume_recovery_code: true)
      @user = user
      @password = password.to_s
      @code = code.to_s
      @consume_recovery_code = consume_recovery_code
    end

    def call
      return failure("password_incorrect") unless @user.authenticate(@password)
      return ServiceResult.success(method: "password") unless @user.totp_enabled?
      return failure("two_factor_code_required") if @code.blank?
      return ServiceResult.success(method: "totp") if @user.verify_totp(@code)

      if @consume_recovery_code && @user.consume_recovery_code!(@code)
        return ServiceResult.success(method: "recovery_code")
      end

      failure("invalid_two_factor_code")
    end

    private

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end

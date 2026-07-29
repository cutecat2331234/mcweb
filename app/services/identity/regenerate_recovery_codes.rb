# frozen_string_literal: true

module Identity
  class RegenerateRecoveryCodes < ApplicationService
    RECOVERY_CODE_COUNT = 10

    def initialize(user:, password:, code:, ip_address: nil, user_agent: nil)
      @user = user
      @password = password
      @code = code
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      return failure("two_factor_not_enabled") unless @user.totp_enabled?

      codes = nil
      verification_method = nil

      User.transaction do
        @user.lock!
        verification = SensitiveActionVerifier.call(
          user: @user,
          password: @password,
          code: @code
        )
        raise VerificationFailed, verification unless verification.success?

        verification_method = verification.value.fetch(:method)
        codes = RECOVERY_CODE_COUNT.times.map { SecureRandom.hex(4).upcase }
        previous_count = Array(@user.recovery_codes).size
        @user.update!(recovery_codes: codes)

        Administration::AuditLogger.call(
          actor: @user,
          action: "identity.totp_recovery_codes_regenerated",
          resource: @user,
          metadata: {
            verification_method: verification_method,
            previous_count: previous_count,
            replacement_count: codes.size
          },
          ip_address: @ip_address,
          user_agent: @user_agent
        )
      end

      ServiceResult.success(codes: codes)
    rescue VerificationFailed => e
      e.result
    end

    class VerificationFailed < StandardError
      attr_reader :result

      def initialize(result)
        @result = result
        super(result.code)
      end
    end

    private

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end

# frozen_string_literal: true

module Identity
  class ChangePassword < ApplicationService
    RATE_LIMIT = 10
    RATE_WINDOW = 15.minutes

    def initialize(user:, current_password:, new_password:, new_password_confirmation:,
                   code: nil, current_session: nil, ip_address: nil, user_agent: nil)
      @user = user
      @current_password = current_password.to_s
      @new_password = new_password.to_s
      @new_password_confirmation = new_password_confirmation.to_s
      @code = code.to_s
      @current_session = current_session
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      return field_failure(:base, "current_session_required") unless valid_current_session?

      limiter = Administration::RateLimiter.call(
        key: "identity:password_change:#{@user.id}:#{@ip_address.presence || 'unknown'}",
        limit: RATE_LIMIT,
        window: RATE_WINDOW
      )
      return limiter if limiter.failure?

      return field_failure(:current_password, "current_password_required") if @current_password.blank?
      return field_failure(:new_password, "new_password_required") if @new_password.blank?
      unless ActiveSupport::SecurityUtils.secure_compare(@new_password, @new_password_confirmation)
        return field_failure(:new_password_confirmation, "password_confirmation_mismatch")
      end
      verification = nil
      revoked_session_count = 0
      changed_at = Time.current

      User.transaction do
        @user.lock!
        locked_session = Session.lock.find_by(id: @current_session.id, user_id: @user.id)
        unless locked_session&.active?
          raise VerificationFailed, field_failure(:base, "current_session_required")
        end

        verification = SensitiveActionVerifier.call(
          user: @user,
          password: @current_password,
          code: @code
        )
        raise VerificationFailed, verification_failure(verification) unless verification.success?
        if @user.authenticate(@new_password)
          raise VerificationFailed, field_failure(:new_password, "password_unchanged")
        end

        @user.update!(
          password: @new_password,
          password_confirmation: @new_password_confirmation,
          password_reset_token_digest: nil,
          password_reset_sent_at: nil,
          failed_login_count: 0,
          locked_until: nil
        )

        Session.active.where(user: @user)
          .where.not(id: locked_session.id)
          .find_each do |session_record|
            session_record.revoke!
            revoked_session_count += 1
          end

        Administration::AuditLogger.call(
          actor: @user,
          action: "identity.password_changed",
          resource: @user,
          metadata: {
            verification_method: verification.value.fetch(:method),
            revoked_session_count: revoked_session_count
          },
          before_state: { other_unrevoked_session_count: revoked_session_count },
          after_state: { other_unrevoked_session_count: 0 },
          ip_address: @ip_address,
          user_agent: @user_agent
        )
      end

      MailDeliveryJob.perform_later(
        "Identity::Mailer",
        "password_changed_email",
        "deliver_now",
        args: [ @user.id, changed_at.iso8601, revoked_session_count ]
      )

      ServiceResult.success(
        user: @user.reload,
        changed_at: changed_at,
        revoked_session_count: revoked_session_count,
        verification_method: verification.value.fetch(:method)
      )
    rescue VerificationFailed => e
      e.result
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(
        code: "validation_failed",
        errors: password_errors(e.record.errors.to_hash)
      )
    end

    class VerificationFailed < StandardError
      attr_reader :result

      def initialize(result)
        @result = result
        super(result.code)
      end
    end

    private

    def valid_current_session?
      @user&.persisted? &&
        @current_session&.persisted? &&
        @current_session.user_id == @user.id &&
        @current_session.active?
    end

    def verification_failure(result)
      field = result.code == "password_incorrect" ? :current_password : :code
      ServiceResult.failure(
        code: result.code,
        errors: { field => [ result.error.presence || result.code ] }
      )
    end

    def field_failure(field, code)
      ServiceResult.failure(code: code, errors: { field => [ code ] })
    end

    def password_errors(errors)
      errors.each_with_object({}) do |(field, messages), mapped|
        destination = case field.to_sym
        when :password then :new_password
        when :password_confirmation then :new_password_confirmation
        else field
        end
        mapped[destination] = messages
      end
    end
  end
end

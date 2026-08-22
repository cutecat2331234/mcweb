# frozen_string_literal: true

module Identity
  class RegisterUser < ApplicationService
    class RegistrationStepFailed < StandardError
      attr_reader :result

      def initialize(result)
        @result = result
        super(result.code.presence || "registration_step_failed")
      end
    end

    def initialize(email:, username:, password:, display_name: nil, locale: "zh-CN", time_zone: "Asia/Shanghai", user_fields: nil, ip_address: nil)
      @email = email.to_s.strip.downcase
      @username = username.to_s.strip
      @password = password
      @display_name = display_name.presence || @username
      @locale = Mcweb::LocaleResolver.normalize(locale) || locale.to_s
      @time_zone = time_zone
      @user_fields = user_fields
      @ip_address = ip_address
    end

    def call
      rate_limit_result = Administration::AbuseRateLimit.call(
        action: :registration,
        account: @email,
        ip_address: @ip_address
      )
      return rate_limit_result if rate_limit_result.failure?

      email_ban_result = Administration::CheckEmailBan.call(email: @email)
      return ServiceResult.failure(error: email_ban_result.error) if email_ban_result.failure?

      auto_verify_email = Mcweb::DeveloperMode.allow?(:skip_email_verification)
      verification_token = generate_token unless auto_verify_email
      verification_requested_at = Time.current if verification_token
      user = nil

      User.transaction do
        Identity::EmailAddressLock.acquire!(@email)
        if Identity::EmailChangeRequest.email_reserved?(@email)
          raise RegistrationStepFailed, ServiceResult.failure(
            error: "email_not_available",
            code: "email_not_available"
          )
        end

        user = User.create!(
          public_id: generate_public_id,
          email: @email,
          username: @username,
          password: @password,
          display_name: @display_name,
          locale: @locale,
          time_zone: @time_zone,
          email_verified: auto_verify_email,
          email_verified_at: auto_verify_email ? Time.current : nil,
          developer_mode_email_verified: auto_verify_email,
          email_verification_token: verification_token,
          email_verification_token_digest: verification_token ? digest_token(verification_token) : nil,
          email_verification_sent_at: verification_requested_at
        )

        if Community::UserFieldDefinition.for_registration.exists?
          field_result = Community::SyncUserFieldValues.call(
            user:,
            values: @user_fields || {},
            context: :registration
          )
          raise RegistrationStepFailed, field_result if field_result.failure?
        end

        assign_default_groups(user)

        audit_result = Administration::AuditLogger.call(
          actor: user,
          action: "identity.register",
          resource: user,
          metadata: { email: @email, username: @username }
        )
        raise RegistrationStepFailed, audit_result if audit_result.failure?

        Identity::EmailVerificationDelivery.record!(user:, token: verification_token) if verification_token
      end

      Mcweb::Events.publish("identity.user.registered", user: user, ip_address: @ip_address)

      ServiceResult.success(user: user, verification_token: verification_token)
    rescue RegistrationStepFailed => e
      e.result
    rescue Operations::DurableEnqueue::InvalidRequest,
           Operations::DurableEnqueue::IdempotencyConflict => e
      Rails.logger.error("[identity.registration] durable_delivery_unavailable error=#{e.class}")
      ServiceResult.failure(
        error: "registration_temporarily_unavailable",
        code: "registration_temporarily_unavailable"
      )
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    # XenForo-style: new members join the configured default primary group(s).
    def assign_default_groups(user)
      defaults = Community::UserGroup.primary_defaults.ordered.to_a
      defaults.each_with_index do |group, index|
        Community::GroupMembership.create!(user: user, user_group: group, is_primary: index.zero?)
      end
    end

    def generate_public_id
      "usr_#{SecureRandom.alphanumeric(16)}"
    end

    def generate_token
      SecureRandom.urlsafe_base64(32)
    end

    def digest_token(token)
      Digest::SHA256.hexdigest(token)
    end
  end
end

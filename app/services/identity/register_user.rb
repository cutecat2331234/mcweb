# frozen_string_literal: true

module Identity
  class RegisterUser < ApplicationService
    def initialize(email:, username:, password:, display_name: nil, locale: "zh-CN", time_zone: "Asia/Shanghai", user_fields: nil, ip_address: nil)
      @email = email.to_s.strip.downcase
      @username = username.to_s.strip
      @password = password
      @display_name = display_name.presence || @username
      @locale = locale
      @time_zone = time_zone
      @user_fields = user_fields
      @ip_address = ip_address
    end

    def call
      email_ban_result = Administration::CheckEmailBan.call(email: @email)
      return ServiceResult.failure(error: email_ban_result.error) if email_ban_result.failure?

      if @ip_address.present?
        rate_limit_result = Administration::RateLimiter.call(
          key: "register:ip:#{@ip_address}",
          limit: 5,
          window: 1.hour
        )
        return ServiceResult.failure(error: "注册过于频繁，请稍后再试。") if rate_limit_result.failure?
      end

      email_rate_result = Administration::RateLimiter.call(
        key: "register:email:#{@email}",
        limit: 3,
        window: 24.hours
      )
      return ServiceResult.failure(error: "该邮箱注册过于频繁，请稍后再试。") if email_rate_result.failure?

      verification_token = generate_token

      user = User.create!(
        public_id: generate_public_id,
        email: @email,
        username: @username,
        password: @password,
        display_name: @display_name,
        locale: @locale,
        time_zone: @time_zone,
        email_verified: false,
        email_verification_token_digest: digest_token(verification_token),
        email_verification_sent_at: Time.current
      )

      if Community::UserFieldDefinition.for_registration.exists?
        field_result = Community::SyncUserFieldValues.call(user: user, values: @user_fields || {}, context: :registration)
        unless field_result.success?
          user.destroy!
          return ServiceResult.failure(errors: field_result.errors)
        end
      end

      assign_default_groups(user)

      Administration::AuditLogger.call(
        actor: user,
        action: "identity.register",
        resource: user,
        metadata: { email: @email, username: @username }
      )

      MailDeliveryJob.perform_later(
        "Identity::Mailer",
        "verification_email",
        "deliver_now",
        args: [ user.id, verification_token ]
      )

      ServiceResult.success(user: user, verification_token: verification_token)
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

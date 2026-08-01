# frozen_string_literal: true

module Identity
  class CloseAccount < ApplicationService
    CONFIRMATION = "DELETE"

    CLOSURE_MODES = %w[anonymize delete_content].freeze

    def initialize(
      user:,
      password:,
      code: nil,
      confirmation:,
      closure_mode: "anonymize",
      reason: nil,
      ip_address: nil,
      user_agent: nil
    )
      @user = user
      @password = password
      @code = code
      @confirmation = confirmation.to_s
      @closure_mode = closure_mode.to_s
      @reason = reason.to_s.strip
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      return failure("account_close_confirmation_invalid") unless @confirmation == CONFIRMATION
      return failure("account_close_mode_invalid") unless CLOSURE_MODES.include?(@closure_mode)

      avatar = nil
      closure_outcome = nil
      User.transaction do
        lock_active_owner_roster!
        @user.lock!
        raise LastActiveOwner if last_active_owner?

        verification = SensitiveActionVerifier.call(
          user: @user,
          password: @password,
          code: @code
        )
        raise VerificationFailed, verification unless verification.success?

        avatar = @user.forum_avatar if @user.respond_to?(:forum_avatar) && @user.forum_avatar.attached?
        before_state = {
          status: @user.status,
          email_verified: @user.email_verified?,
          totp_enabled: @user.totp_enabled?,
          requested_closure_mode: @closure_mode
        }

        closure_outcome = apply_content_outcome!
        @user.update!(
          email: anonymized_email,
          username: anonymized_username,
          display_name: nil,
          bio: nil,
          email_verified: false,
          email_verified_at: nil,
          developer_mode_email_verified: false,
          developer_mode_relaxed_password: false,
          email_verification_token_digest: nil,
          email_verification_sent_at: nil,
          password_reset_token_digest: nil,
          password_reset_sent_at: nil,
          totp_enabled: false,
          totp_secret: nil,
          recovery_codes: nil,
          totp_recovery_token_digest: nil,
          totp_recovery_sent_at: nil,
          account_closure_outcome: closure_outcome,
          account_closed_at: Time.current
        )
        @user.soft_delete!

        Administration::AuditLogger.call(
          actor: @user,
          action: "identity.account_closed",
          resource: @user,
          metadata: {
            verification_method: verification.value.fetch(:method),
            requested_closure_mode: @closure_mode,
            closure_outcome: closure_outcome,
            policy: "profile_anonymized_financial_and_governance_records_retained"
          },
          before_state: before_state,
          after_state: {
            status: "deleted",
            profile_anonymized: true,
            sessions_revoked: true,
            closure_outcome: closure_outcome
          },
          reason: @reason.presence,
          ip_address: @ip_address,
          user_agent: @user_agent
        )
      end

      avatar&.purge_later
      ServiceResult.success(user: @user)
    rescue VerificationFailed => e
      e.result
    rescue LastActiveOwner
      failure("last_owner_account_cannot_close")
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    class VerificationFailed < StandardError
      attr_reader :result

      def initialize(result)
        @result = result
        super(result.code)
      end
    end

    class LastActiveOwner < StandardError; end

    private

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end

    def last_active_owner?
      @user.account_owner? &&
        @user.active? &&
        !User.where(account_type: :owner, status: :active).where.not(id: @user.id).exists?
    end

    def lock_active_owner_roster!
      User
        .where(account_type: :owner, status: :active)
        .order(:id)
        .lock
        .load
    end

    def apply_content_outcome!
      return "legally_retained" if DataGovernance::RetentionHold.effective.exists?(target: @user)
      return "stable_anonymous_author" unless @closure_mode == "delete_content"

      blocked = false
      Community::Topic.where(user: @user).find_each do |topic|
        policy = DataGovernance::DeletionPolicy.call(target: topic)
        if policy.value.fetch(:allowed)
          topic.update!(title: I18n.t("mcweb.identity.deleted_content_title"), status: :deleted, deleted_at: Time.current)
        else
          blocked = true
        end
      end
      Community::Post.where(user: @user).find_each do |post|
        policy = DataGovernance::DeletionPolicy.call(target: post)
        if policy.value.fetch(:allowed)
          post.update!(body: I18n.t("mcweb.identity.deleted_content_body"), status: :deleted, deleted_at: Time.current)
        else
          blocked = true
        end
      end
      Community::Message.where(user: @user).find_each do |message|
        policy = DataGovernance::DeletionPolicy.call(target: message)
        if policy.value.fetch(:allowed)
          message.update!(body: I18n.t("mcweb.identity.deleted_content_body"), deleted_at: Time.current)
        else
          blocked = true
        end
      end

      blocked ? "legally_retained" : "authored_content_deleted"
    end

    def anonymized_username
      "deleted_#{anonymized_identifier}"
    end

    def anonymized_email
      "deleted+#{anonymized_identifier}@invalid.local"
    end

    def anonymized_identifier
      Digest::SHA256.hexdigest(@user.public_id.to_s).first(20)
    end
  end
end

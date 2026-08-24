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
      closure_results = nil
      replayed = false
      closed_at = Time.current
      User.transaction do
        lock_active_owner_roster!
        @user.lock!
        if account_already_closed?
          closure_results = stored_closure_results
          replayed = true
          next
        end
        raise LastActiveOwner if last_active_owner?

        verification = SensitiveActionVerifier.call(
          user: @user,
          password: @password,
          code: @code
        )
        raise VerificationFailed, verification unless verification.success?

        avatar = @user.forum_avatar if @user.respond_to?(:forum_avatar) && @user.forum_avatar.attached?
        context = AccountClosure::Context.new(
          user: @user,
          closure_mode: @closure_mode,
          reason: @reason,
          at: closed_at
        )
        lifecycle = AccountClosure::Lifecycle.call(
          context:,
          finalize: lambda do |contributions|
            finalize_account!(
              contributions:,
              verification_method: verification.value.fetch(:method),
              closed_at:
            )
          end
        )
        raise LifecycleFailed, lifecycle unless lifecycle.success?

        closure_results = lifecycle.value.fetch(:contributions)
      end

      avatar&.purge_later unless replayed
      ServiceResult.success(
        user: @user,
        closure_results:,
        replayed:
      )
    rescue VerificationFailed => e
      e.result
    rescue LifecycleFailed => e
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

    class LifecycleFailed < StandardError
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

    def account_already_closed?
      @user.deleted? && @user.account_closed_at.present?
    end

    def stored_closure_results
      return @user.account_closure_results if @user.account_closure_results.present?

      {
        "identity.profile" => {
          "status" => "completed",
          "details" => { "outcome" => "profile_anonymized" }
        },
        "identity.authored_content" => {
          "status" => "completed",
          "details" => {
            "outcome" => @user.account_closure_outcome.presence || "stable_anonymous_author"
          }
        }
      }
    end

    def finalize_account!(contributions:, verification_method:, closed_at:)
      closure_outcome = contributions.dig(
        "identity.authored_content",
        "details",
        "outcome"
      ) || "stable_anonymous_author"
      closure_results = contributions.merge(
        "identity.profile" => {
          "status" => "completed",
          "details" => {
            "outcome" => "profile_anonymized",
            "sessions_revoked" => true,
            "pending_email_changes_cancelled" => true
          }
        }
      )
      before_state = {
        status: @user.status,
        email_verified: @user.email_verified?,
        totp_enabled: @user.totp_enabled?,
        requested_closure_mode: @closure_mode
      }

      cancel_email_changes!(at: closed_at)
      @user.update!(
        email: anonymized_email,
        username: anonymized_username,
        display_name: nil,
        bio: nil,
        forum_profile_activity_public: false,
        email_verified: false,
        email_verified_at: nil,
        developer_mode_email_verified: false,
        developer_mode_relaxed_password: false,
        email_verification_token: nil,
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
        account_closure_results: closure_results,
        account_closed_at: closed_at
      )
      @user.soft_delete!

      audit_result = Administration::AuditLogger.call(
        actor: @user,
        action: "identity.account_closed",
        resource: @user,
        metadata: {
          verification_method:,
          requested_closure_mode: @closure_mode,
          closure_outcome:,
          closure_results:,
          policy: "profile_anonymized_financial_and_governance_records_retained"
        },
        before_state:,
        after_state: {
          status: "deleted",
          profile_anonymized: true,
          sessions_revoked: true,
          closure_outcome:,
          contribution_count: closure_results.size
        },
        reason: @reason.presence,
        ip_address: @ip_address,
        user_agent: @user_agent
      )
      raise AccountClosureFinalizationFailed unless audit_result.success?

      closure_results
    end

    def cancel_email_changes!(at:)
      @user.email_change_requests
        .where(status: %w[pending confirmed])
        .update_all(
          status: "superseded",
          confirmation_token_ciphertext: nil,
          revocation_token_ciphertext: nil,
          updated_at: at
        )
    end

    class AccountClosureFinalizationFailed < StandardError; end

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

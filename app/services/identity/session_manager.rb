# frozen_string_literal: true

module Identity
  class SessionManager < ApplicationService
    DEFAULT_TTL = 24.hours
    REMEMBER_ME_TTL = 30.days
    VERIFIED_CREDENTIALS_CONTEXT = :verified_credentials
    DEVELOPER_MODE_CONTEXT = :developer_mode
    TEST_CONTEXT = :test

    def initialize(
      user: nil,
      session: nil,
      ip_address: nil,
      user_agent: nil,
      remember_me: false,
      action: :create,
      credential_snapshot: nil,
      authentication_context: nil
    )
      @user = user
      @session = session
      @ip_address = ip_address
      @user_agent = user_agent
      @remember_me = remember_me
      @action = action
      @credential_snapshot = credential_snapshot
      @authentication_context = authentication_context&.to_sym
    end

    def call
      case @action
      when :create then create_session
      when :revoke then revoke_session
      when :revoke_all then revoke_all_sessions
      else
        ServiceResult.failure(
          error: I18n.t("mcweb.user_copy.unknown_session_action", action: @action)
        )
      end
    end

    private

    def create_session
      User.transaction do
        locked_user = User.lock.find_by(id: @user&.id)
        unless locked_user&.session_eligible?
          next ServiceResult.failure(
            error: "session_ineligible",
            code: "session_ineligible"
          )
        end
        unless session_creation_authorized?(locked_user)
          next ServiceResult.failure(
            error: "session_credential_stale",
            code: "session_credential_stale"
          )
        end

        token = generate_token
        expires_at = (@remember_me ? REMEMBER_ME_TTL : DEFAULT_TTL).from_now

        session = Session.create!(
          user: locked_user,
          token_digest: digest_token(token),
          ip_address: @ip_address,
          user_agent: @user_agent,
          remember_me: @remember_me,
          developer_mode: Mcweb::DeveloperMode.enabled?,
          last_active_at: Time.current,
          expires_at: expires_at
        )

        ServiceResult.success(session: session, token: token)
      end
    end

    def revoke_session
      return ServiceResult.failure(error: :session_is_required) unless @session

      @session.update!(revoked_at: Time.current) unless @session.revoked_at?
      ServiceResult.success(@session)
    end

    def revoke_all_sessions
      return ServiceResult.failure(error: :user_is_required) unless @user

      Session.where(user: @user, revoked_at: nil).find_each do |session|
        session.update!(revoked_at: Time.current)
      end

      ServiceResult.success(@user)
    end

    def generate_token
      SecureRandom.urlsafe_base64(32)
    end

    def digest_token(token)
      Digest::SHA256.hexdigest(token)
    end

    def session_creation_authorized?(locked_user)
      case @authentication_context
      when VERIFIED_CREDENTIALS_CONTEXT
        CredentialSnapshot.valid?(locked_user, @credential_snapshot)
      when DEVELOPER_MODE_CONTEXT
        Mcweb::DeveloperMode.enabled?
      when TEST_CONTEXT
        Rails.env.test?
      else
        false
      end
    end
  end
end

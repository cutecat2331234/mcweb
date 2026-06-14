# frozen_string_literal: true

module Identity
  class SessionManager < ApplicationService
    DEFAULT_TTL = 24.hours
    REMEMBER_ME_TTL = 30.days

    def initialize(user: nil, session: nil, ip_address: nil, user_agent: nil, remember_me: false, action: :create)
      @user = user
      @session = session
      @ip_address = ip_address
      @user_agent = user_agent
      @remember_me = remember_me
      @action = action
    end

    def call
      case @action
      when :create then create_session
      when :revoke then revoke_session
      when :revoke_all then revoke_all_sessions
      else
        ServiceResult.failure(error: "Unknown session action: #{@action}")
      end
    end

    private

    def create_session
      token = generate_token
      expires_at = (@remember_me ? REMEMBER_ME_TTL : DEFAULT_TTL).from_now

      session = Session.create!(
        user: @user,
        token_digest: digest_token(token),
        ip_address: @ip_address,
        user_agent: @user_agent,
        remember_me: @remember_me,
        last_active_at: Time.current,
        expires_at: expires_at
      )

      ServiceResult.success(session: session, token: token)
    end

    def revoke_session
      return ServiceResult.failure(error: "Session is required.") unless @session

      @session.update!(revoked_at: Time.current) unless @session.revoked_at?
      ServiceResult.success(@session)
    end

    def revoke_all_sessions
      return ServiceResult.failure(error: "User is required.") unless @user

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
  end
end

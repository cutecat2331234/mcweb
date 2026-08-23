# frozen_string_literal: true

require "test_helper"

module Identity
  class EnableTotpTest < ActiveSupport::TestCase
    setup do
      @user = create_user
      @user.setup_totp!
      current_result = create_test_session(
        @user,
        ip_address: "127.0.0.1",
        user_agent: "Current device"
      )
      @current_session = current_result.value.fetch(:session)
      @current_token = current_result.value.fetch(:token)
    end

    test "reauthenticates enrollment, revokes other sessions, rotates the current token, audits, and notifies" do
      first_other = create_test_session(@user).value.fetch(:session)
      second_other = create_test_session(@user).value.fetch(:session)
      expired_session = create_test_session(@user).value.fetch(:session)
      expired_session.update!(expires_at: 1.minute.ago)
      code = current_code
      original_codes = Array(@user.recovery_codes)
      captured = nil

      result = MailDeliveryJob.stub(:perform_later, ->(*args, **kwargs) { captured = [ args, kwargs ] }) do
        enable_totp(code: code)
      end

      assert result.success?
      assert @user.reload.totp_enabled?
      assert_equal original_codes, result.value.fetch(:recovery_codes)
      assert_equal 2, result.value.fetch(:revoked_session_count)
      refute result.value.fetch(:replayed)
      assert first_other.reload.revoked?
      assert second_other.reload.revoked?
      refute expired_session.reload.revoked?
      refute @current_session.reload.revoked?

      rotated_token = result.value.fetch(:session_token)
      refute_equal @current_token, rotated_token
      assert_equal Session.digest_token(rotated_token), @current_session.token_digest
      refute Session.exists?(token_digest: Session.digest_token(@current_token))

      audit = AuditLog.find_by!(action: "identity.totp_enabled", resource_id: @user.id)
      assert_equal "password_and_totp", audit.metadata.fetch("verification_method")
      assert_equal 2, audit.metadata.fetch("revoked_session_count")
      assert_equal true, audit.after_state.fetch("current_session_token_rotated")
      assert_equal "127.0.0.9", audit.ip_address
      assert_equal "Enrollment test", audit.user_agent

      serialized_audit = [ audit.metadata, audit.before_state, audit.after_state ].to_json
      [ @user.totp_secret, code, "password123", @current_token, rotated_token, *original_codes ].each do |secret|
        refute_includes serialized_audit, secret
      end

      assert_equal [ "Identity::Mailer", "totp_enabled_email", "deliver_now" ], captured.first
      assert_equal @user.id, captured.last.fetch(:args).first
      assert_equal 2, captured.last.fetch(:args).last
    end

    test "rejects the wrong password without enabling totp or changing sessions" do
      other_session = create_test_session(@user).value.fetch(:session)
      original_digest = @current_session.token_digest
      deliveries = 0

      result = MailDeliveryJob.stub(:perform_later, ->(*_args, **_kwargs) { deliveries += 1 }) do
        enable_totp(password: "wrong-password")
      end

      assert result.failure?
      assert_equal "password_incorrect", result.code
      refute @user.reload.totp_enabled?
      refute other_session.reload.revoked?
      assert_equal original_digest, @current_session.reload.token_digest
      assert_equal 0, deliveries
      refute AuditLog.exists?(action: "identity.totp_enabled", resource_id: @user.id)
    end

    test "rejects an invalid authenticator code after password verification" do
      other_session = create_test_session(@user).value.fetch(:session)

      result = enable_totp(code: "not-a-code")

      assert result.failure?
      assert_equal "invalid_two_factor_code", result.code
      refute @user.reload.totp_enabled?
      refute other_session.reload.revoked?
      refute AuditLog.exists?(action: "identity.totp_enabled", resource_id: @user.id)
    end

    test "rejects a stale browser secret before changing enrollment state" do
      stale_secret = ROTP::Base32.random

      result = enable_totp(
        secret: stale_secret,
        code: ROTP::TOTP.new(stale_secret).now
      )

      assert result.failure?
      assert_equal "totp_setup_stale", result.code
      refute @user.reload.totp_enabled?
      refute @current_session.reload.revoked?
      refute AuditLog.exists?(action: "identity.totp_enabled", resource_id: @user.id)
    end

    test "rolls back enrollment and session changes when the audit record cannot be saved" do
      other_session = create_test_session(@user).value.fetch(:session)
      original_digest = @current_session.token_digest
      deliveries = 0
      audit_failure = ServiceResult.failure(error: "audit_failed", code: "audit_failed")

      result = Administration::AuditLogger.stub(:call, audit_failure) do
        MailDeliveryJob.stub(:perform_later, ->(*_args, **_kwargs) { deliveries += 1 }) do
          enable_totp
        end
      end

      assert result.failure?
      assert_equal "totp_enable_audit_failed", result.code
      refute @user.reload.totp_enabled?
      refute other_session.reload.revoked?
      assert_equal original_digest, @current_session.reload.token_digest
      assert_equal 0, deliveries
    end

    test "replays confirmation for the same enabled secret without duplicate effects" do
      deliveries = []
      first = MailDeliveryJob.stub(:perform_later, ->(*args, **kwargs) { deliveries << [ args, kwargs ] }) do
        enable_totp
      end
      first_digest = @current_session.reload.token_digest

      replay = MailDeliveryJob.stub(:perform_later, ->(*args, **kwargs) { deliveries << [ args, kwargs ] }) do
        enable_totp
      end

      assert first.success?
      assert replay.success?
      assert replay.value.fetch(:replayed)
      assert_nil replay.value[:session_token]
      assert_equal first_digest, @current_session.reload.token_digest
      assert_equal first.value.fetch(:recovery_codes), replay.value.fetch(:recovery_codes)
      assert_equal 1, AuditLog.where(action: "identity.totp_enabled", resource_id: @user.id).count
      assert_equal 1, deliveries.size
    end

    test "fails closed when the current session is missing or belongs to another user" do
      other_user = create_user
      foreign_session = create_test_session(other_user).value.fetch(:session)

      [ nil, foreign_session ].each do |session_record|
        result = enable_totp(current_session: session_record)

        assert result.failure?
        assert_equal "totp_current_session_required", result.code
      end

      refute @user.reload.totp_enabled?
    end

    private

    def enable_totp(
      secret: @user.totp_secret,
      password: "password123",
      code: current_code,
      current_session: @current_session
    )
      EnableTotp.call(
        user: @user,
        secret: secret,
        password: password,
        code: code,
        current_session: current_session,
        ip_address: "127.0.0.9",
        user_agent: "Enrollment test"
      )
    end

    def current_code
      ROTP::TOTP.new(@user.totp_secret).now
    end
  end
end

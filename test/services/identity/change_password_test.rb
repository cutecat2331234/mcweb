# frozen_string_literal: true

require "test_helper"

module Identity
  class ChangePasswordTest < ActiveSupport::TestCase
    setup do
      @user = create_user
      current_result = create_test_session(
        @user,
        ip_address: "127.0.0.1",
        user_agent: "Current device"
      )
      @current_session = current_result.value.fetch(:session)
      @current_token = current_result.value.fetch(:token)
    end

    test "changes the password, preserves the current session, and revokes every other session" do
      first_other = create_test_session(@user).value.fetch(:session)
      second_other = create_test_session(@user).value.fetch(:session)
      expired_session = create_test_session(@user).value.fetch(:session)
      expired_session.update!(expires_at: 1.minute.ago)
      reset_token = SecureRandom.urlsafe_base64(32)
      totp_recovery_token = SecureRandom.urlsafe_base64(32)
      @user.update!(
        password_reset_token: reset_token,
        password_reset_token_digest: Digest::SHA256.hexdigest(reset_token),
        password_reset_sent_at: Time.current,
        totp_recovery_token: totp_recovery_token,
        totp_recovery_token_digest: Digest::SHA256.hexdigest(totp_recovery_token),
        totp_recovery_sent_at: Time.current,
        failed_login_count: 4,
        locked_until: 10.minutes.from_now
      )
      captured = nil

      result = MailDeliveryJob.stub(:perform_later, ->(*args, **kwargs) { captured = [ args, kwargs ] }) do
        ChangePassword.call(
          user: @user,
          current_password: "password123",
          new_password: "replacement456",
          new_password_confirmation: "replacement456",
          current_session: @current_session,
          ip_address: "127.0.0.9",
          user_agent: "Password test"
        )
      end

      assert result.success?
      @user.reload
      assert @user.authenticate("replacement456")
      refute @user.authenticate("password123")
      rotated_token = result.value.fetch(:session_token)
      refute_equal @current_token, rotated_token
      assert_equal Session.digest_token(rotated_token), @current_session.reload.token_digest
      refute Session.exists?(token_digest: Session.digest_token(@current_token))
      refute @current_session.reload.revoked?
      assert first_other.reload.revoked?
      assert second_other.reload.revoked?
      refute expired_session.reload.revoked?
      assert_nil @user.password_reset_token
      assert_nil @user.password_reset_token_digest
      assert_nil @user.password_reset_sent_at
      assert_nil @user.totp_recovery_token
      assert_nil @user.totp_recovery_token_digest
      assert_nil @user.totp_recovery_sent_at
      assert_equal 0, @user.failed_login_count
      assert_nil @user.locked_until
      assert_equal 2, result.value.fetch(:revoked_session_count)

      audit = AuditLog.find_by!(action: "identity.password_changed", resource_id: @user.id)
      assert_equal "password", audit.metadata.fetch("verification_method")
      assert_equal 2, audit.metadata.fetch("revoked_session_count")
      assert_equal "127.0.0.9", audit.ip_address
      assert_equal "Password test", audit.user_agent
      refute_includes audit.to_json, "password123"
      refute_includes audit.to_json, "replacement456"
      refute_includes audit.to_json, @current_token
      refute_includes audit.to_json, rotated_token

      assert_equal [ "Identity::Mailer", "password_changed_email", "deliver_now" ], captured.first
      assert_equal @user.id, captured.last.fetch(:args).first
      assert_equal 2, captured.last.fetch(:args).last
    end

    test "rejects the wrong current password without changing credentials or sessions" do
      other_session = create_test_session(@user).value.fetch(:session)

      result = ChangePassword.call(
        user: @user,
        current_password: "wrong-password",
        new_password: "replacement456",
        new_password_confirmation: "replacement456",
        current_session: @current_session
      )

      assert result.failure?
      assert_equal "password_incorrect", result.code
      assert result.errors.key?(:current_password)
      assert @user.reload.authenticate("password123")
      refute other_session.reload.revoked?
      refute AuditLog.exists?(action: "identity.password_changed", resource_id: @user.id)
    end

    test "fails closed when the current session is missing or belongs to another user" do
      other_user = create_user
      foreign_session = create_test_session(other_user).value.fetch(:session)

      [ nil, foreign_session ].each do |session_record|
        result = ChangePassword.call(
          user: @user,
          current_password: "password123",
          new_password: "replacement456",
          new_password_confirmation: "replacement456",
          current_session: session_record
        )

        assert result.failure?
        assert_equal "current_session_required", result.code
      end

      assert @user.reload.authenticate("password123")
    end

    test "requires the two-factor proof and records its verification method" do
      @user.setup_totp!
      @user.update!(totp_enabled: true)

      missing = ChangePassword.call(
        user: @user,
        current_password: "password123",
        new_password: "replacement456",
        new_password_confirmation: "replacement456",
        current_session: @current_session
      )
      assert missing.failure?
      assert_equal "two_factor_code_required", missing.code
      assert missing.errors.key?(:code)

      code = ROTP::TOTP.new(@user.totp_secret).now
      result = MailDeliveryJob.stub(:perform_later, true) do
        ChangePassword.call(
          user: @user,
          current_password: "password123",
          new_password: "replacement456",
          new_password_confirmation: "replacement456",
          code: code,
          current_session: @current_session
        )
      end

      assert result.success?
      assert_equal "totp", result.value.fetch(:verification_method)
    end

    test "rejects mismatched, reused, and too-short passwords" do
      mismatch = ChangePassword.call(
        user: @user,
        current_password: "password123",
        new_password: "replacement456",
        new_password_confirmation: "different456",
        current_session: @current_session
      )
      assert_equal "password_confirmation_mismatch", mismatch.code

      reused = ChangePassword.call(
        user: @user,
        current_password: "password123",
        new_password: "password123",
        new_password_confirmation: "password123",
        current_session: @current_session
      )
      assert_equal "password_unchanged", reused.code

      too_short = ChangePassword.call(
        user: @user,
        current_password: "password123",
        new_password: "short",
        new_password_confirmation: "short",
        current_session: @current_session
      )
      assert_equal "validation_failed", too_short.code
      assert too_short.errors.key?(:new_password)
      assert @user.reload.authenticate("password123")
    end
  end
end

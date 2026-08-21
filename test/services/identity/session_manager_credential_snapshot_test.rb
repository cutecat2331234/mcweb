# frozen_string_literal: true

require "test_helper"

module Identity
  class SessionManagerCredentialSnapshotTest < ActiveSupport::TestCase
    setup do
      @user = create_user
    end

    test "verified credentials issue an opaque snapshot accepted under the user row lock" do
      credentials = VerifyCredentials.call(
        email: @user.email,
        password: "password123",
        ip_address: "127.0.0.1"
      )

      assert credentials.success?
      snapshot = credentials.value.fetch(:credential_snapshot)
      refute_equal @user.password_digest, snapshot
      refute_includes snapshot, @user.password_digest

      result = SessionManager.call(
        user: @user,
        credential_snapshot: snapshot,
        authentication_context: SessionManager::VERIFIED_CREDENTIALS_CONTEXT
      )

      assert result.success?
      assert result.value.fetch(:session).persisted?
    end

    test "password replacement expires a previously verified credential snapshot" do
      snapshot = CredentialSnapshot.issue(@user)
      @user.update!(
        password: "replacement456",
        password_confirmation: "replacement456"
      )

      assert_no_difference -> { @user.sessions.count } do
        result = SessionManager.call(
          user: @user,
          credential_snapshot: snapshot,
          authentication_context: SessionManager::VERIFIED_CREDENTIALS_CONTEXT
        )

        assert result.failure?
        assert_equal "session_credential_stale", result.code
      end
    end

    test "non-password session creation requires an explicit restricted context" do
      missing_context = SessionManager.call(user: @user)
      developer_context = SessionManager.call(
        user: @user,
        authentication_context: SessionManager::DEVELOPER_MODE_CONTEXT
      )
      test_context = create_test_session(@user)

      assert missing_context.failure?
      assert_equal "session_credential_stale", missing_context.code
      assert developer_context.failure?
      assert_equal "session_credential_stale", developer_context.code
      assert test_context.success?
    end
  end

  class SessionCreationPasswordRaceTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    setup do
      @user = create_user
      current_result = create_test_session(@user)
      @current_session = current_result.value.fetch(:session)
    end

    teardown do
      user_id = @user&.id
      AuditLog.where(actor_id: user_id).or(
        AuditLog.where(resource_type: "User", resource_id: user_id)
      ).delete_all
      Session.where(user_id: user_id).delete_all
      RateLimitCounter.where("key LIKE ?", "identity:password_change:#{user_id}:%").delete_all
      User.where(id: user_id).delete_all
    end

    test "a session created first is revoked by the password change that follows" do
      snapshot = CredentialSnapshot.issue(@user)
      manager_entered = Queue.new
      release_manager = Queue.new
      change_started = Queue.new
      manager_outcome = Queue.new
      change_outcome = Queue.new

      manager_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          begin
            result = User.transaction do
              locked_user = User.lock.find(@user.id)
              manager_entered << true
              release_manager.pop
              SessionManager.call(
                user: locked_user,
                credential_snapshot: snapshot,
                authentication_context: SessionManager::VERIFIED_CREDENTIALS_CONTEXT
              )
            end
            manager_outcome << result
          rescue StandardError => e
            manager_outcome << e
          end
        end
      end

      manager_entered.pop
      change_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          begin
            change_started << true
            result = MailDeliveryJob.stub(:perform_later, true) do
              ChangePassword.call(
                user: User.find(@user.id),
                current_password: "password123",
                new_password: "replacement456",
                new_password_confirmation: "replacement456",
                current_session: Session.find(@current_session.id),
                ip_address: "127.0.0.8"
              )
            end
            change_outcome << result
          rescue StandardError => e
            change_outcome << e
          end
        end
      end

      change_started.pop
      release_manager << true
      manager_thread.join
      change_thread.join

      manager_result = manager_outcome.pop
      change_result = change_outcome.pop
      raise manager_result if manager_result.is_a?(Exception)
      raise change_result if change_result.is_a?(Exception)

      assert manager_result.success?
      assert change_result.success?
      assert manager_result.value.fetch(:session).reload.revoked?
      assert @user.reload.authenticate("replacement456")
    end
  end
end

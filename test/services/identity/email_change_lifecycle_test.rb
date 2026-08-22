# frozen_string_literal: true

require "test_helper"

module Identity
  class EmailChangeLifecycleTest < ActiveSupport::TestCase
    setup do
      @user = create_user(email: "email-owner-#{SecureRandom.hex(4)}@example.com")
      @current_session = create_test_session(@user).value.fetch(:session)
    end

    test "request reserves the pending address and records secret-safe notices to both addresses" do
      result = request_change("pending@example.com")

      assert_predicate result, :success?
      request = result.value.fetch(:email_change_request).reload
      assert_predicate request, :pending?
      assert_equal @user.email, request.original_email
      assert_equal "pending@example.com", request.requested_email
      assert_equal @user.email, @user.reload.email

      intents = Operations::DurableEnqueueIntent.where(
        handler_key: EmailChangeDelivery::HANDLER_KEY,
        source_id: request.id
      ).order(:id)
      assert_equal 2, intents.count
      assert_equal %w[confirmation security_notice], intents.map { |intent| intent.arguments.fetch("kind") }.sort
      serialized = intents.map(&:attributes).to_json
      refute_includes serialized, request.confirmation_token
      refute_includes serialized, request.revocation_token

      confirmation = Identity::Mailer.email_change_confirmation(
        request.id,
        request.confirmation_token
      )
      notice = Identity::Mailer.email_change_security_notice(
        request.id,
        request.revocation_token
      )
      assert_equal [ "pending@example.com" ], confirmation.to
      assert_equal [ request.original_email ], notice.to
    end

    test "confirmation atomically switches ownership and preserves only the initiating session" do
      other_session = create_test_session(@user).value.fetch(:session)
      request = request_change("confirmed@example.com").value.fetch(:email_change_request)
      token = request.confirmation_token

      result = ConfirmEmailChange.call(token:, ip_address: "127.0.0.1")

      assert_predicate result, :success?
      refute result.value.fetch(:replayed)
      assert_equal "confirmed@example.com", @user.reload.email
      assert @user.email_verified?
      assert_predicate request.reload, :confirmed?
      refute @current_session.reload.revoked?
      assert other_session.reload.revoked?

      replay = ConfirmEmailChange.call(token:, ip_address: "127.0.0.1")
      assert_predicate replay, :success?
      assert replay.value.fetch(:replayed)
      assert_equal 1, AuditLog.where(action: "identity.email_changed", resource_id: @user.id).count
    end

    test "old address can cancel a pending change without changing login identity" do
      request = request_change("cancelled@example.com").value.fetch(:email_change_request)
      confirmation_token = request.confirmation_token
      revocation_token = request.revocation_token

      result = RevokeEmailChange.call(token: revocation_token, ip_address: "127.0.0.1")

      assert_predicate result, :success?
      refute result.value.fetch(:reverted)
      assert_predicate request.reload, :revoked?
      assert_equal request.original_email, @user.reload.email
      refute @current_session.reload.revoked?
      assert_predicate ConfirmEmailChange.call(token: confirmation_token), :failure?
    end

    test "old address can reverse a confirmed change and revoke every session" do
      other_session = create_test_session(@user).value.fetch(:session)
      request = request_change("reversible@example.com").value.fetch(:email_change_request)
      original_email = request.original_email
      revocation_token = request.revocation_token
      ConfirmEmailChange.call(token: request.confirmation_token)

      result = RevokeEmailChange.call(token: revocation_token, ip_address: "127.0.0.1")

      assert_predicate result, :success?
      assert result.value.fetch(:reverted)
      assert_equal original_email, @user.reload.email
      assert @current_session.reload.revoked?
      assert other_session.reload.revoked?
      assert request.reload.reverted_at.present?

      replay = RevokeEmailChange.call(token: revocation_token, ip_address: "127.0.0.1")
      assert_predicate replay, :success?
      assert replay.value.fetch(:replayed)
      assert replay.value.fetch(:reverted)
    end

    test "expired confirmation is rejected and releases the pending address" do
      request = request_change("expired@example.com").value.fetch(:email_change_request)

      result = ConfirmEmailChange.call(
        token: request.confirmation_token,
        at: request.expires_at + 1.second
      )

      assert_predicate result, :failure?
      assert_equal "invalid_or_expired_email_change_token", result.code
      assert_predicate request.reload, :expired?
      refute EmailChangeRequest.email_reserved?("expired@example.com")
      assert_equal request.original_email, @user.reload.email
    end

    test "a replacement request supersedes the previous token and leaves one pending row" do
      first = request_change("first-pending@example.com").value.fetch(:email_change_request)
      first_token = first.confirmation_token
      second = request_change("second-pending@example.com").value.fetch(:email_change_request)

      assert_predicate first.reload, :superseded?
      assert_predicate second.reload, :pending?
      assert_equal 1, @user.email_change_requests.pending.count
      assert_predicate ConfirmEmailChange.call(token: first_token), :failure?
    end

    test "a reserved address cannot be registered by another account" do
      request_change("reserved@example.com")

      result = RegisterUser.call(
        email: "reserved@example.com",
        username: "reserved#{SecureRandom.hex(4)}",
        password: "password123"
      )

      assert_predicate result, :failure?
      assert_equal "email_not_available", result.code
    end

    test "expired reversal token cannot change the confirmed address" do
      request = request_change("permanent@example.com").value.fetch(:email_change_request)
      revocation_token = request.revocation_token
      ConfirmEmailChange.call(token: request.confirmation_token, at: request.expires_at - 1.second)

      result = RevokeEmailChange.call(
        token: revocation_token,
        at: request.reload.revert_expires_at + 1.second
      )

      assert_predicate result, :failure?
      assert_equal "invalid_or_expired_email_change_token", result.code
      assert_equal "permanent@example.com", @user.reload.email
    end

    private

    def request_change(email)
      ChangeEmail.call(
        user: @user,
        email:,
        password: "password123",
        current_session: @current_session,
        ip_address: "127.0.0.1",
        user_agent: "Email lifecycle test"
      )
    end
  end
end

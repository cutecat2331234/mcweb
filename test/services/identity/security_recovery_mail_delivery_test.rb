# frozen_string_literal: true

require "test_helper"
require "timeout"

module Identity
  class SecurityRecoveryMailDeliveryTest < ActiveSupport::TestCase
    setup do
      clear_enqueued_jobs
      ActionMailer::Base.deliveries.clear
      @user = create_user
    end

    test "password reset records one pending secret-safe durable intent and audit" do
      callbacks = []
      result = nil
      ActiveRecord.stub(:after_all_transactions_commit, ->(&callback) { callbacks << callback }) do
        result = ResetPassword.call(
          email: @user.email,
          ip_address: "203.0.113.8",
          user_agent: "Recovery test"
        )
      end

      assert_predicate result, :success?
      token = result.value.fetch(:reset_token)
      intent = result.value.fetch(:delivery_intent)
      audit = AuditLog.find_by!(
        action: "identity.password_reset_requested",
        resource_id: @user.id
      )
      @user.reload

      assert_equal 1, callbacks.size
      assert_equal "pending", result.value.dig(:delivery_status, :status)
      assert_equal "password_reset", intent.arguments.fetch("purpose")
      assert_equal Digest::SHA256.hexdigest(token), intent.arguments.fetch("token_digest")
      assert_equal token, @user.password_reset_token
      refute_equal token, @user.password_reset_token_ciphertext
      refute_includes intent.attributes.to_json, token
      refute_includes audit.attributes.to_json, token
      assert_nil audit.actor_id
      assert_equal "anonymous", audit.metadata.fetch("requester")
      assert_equal "203.0.113.8", audit.ip_address
      assert_equal "Recovery test", audit.user_agent
      assert_equal intent.public_id, audit.metadata.fetch("delivery_intent_public_id")
      assert_equal "issued", audit.metadata.fetch("request_kind")
      assert_enqueued_with(job: Operations::DispatchDurableIntentJob) do
        callbacks.sole.call
      end
      refute_includes enqueued_jobs.to_json, token
    end

    test "shared handler bounds automatic retry and staff reopen authority" do
      entry = Operations::DurableEnqueueCatalog.entry(
        SecurityRecoveryMailDelivery::HANDLER_KEY
      )

      assert_equal "mailers", entry.queue_name
      assert_equal "at_least_once", entry.replay_contract
      assert_equal 5, entry.max_attempts
      assert_equal [ 30, 120, 300, 900 ], entry.retry_delays
      assert_equal "system.jobs.manage", entry.manual_reopen_permission
    end

    test "duplicate requests inside the cooldown reuse the token and intent" do
      callbacks = []
      first = nil
      second = nil
      ActiveRecord.stub(:after_all_transactions_commit, ->(&callback) { callbacks << callback }) do
        travel_to Time.zone.parse("2026-08-24 12:00:00") do
          first = ResetPassword.call(email: @user.email, ip_address: "203.0.113.9")
          second = ResetPassword.call(email: @user.email, ip_address: "203.0.113.9")
        end
      end

      assert_equal first.value.fetch(:reset_token), second.value.fetch(:reset_token)
      assert second.value.fetch(:duplicate)
      assert_equal first.value.fetch(:delivery_intent).id,
                   second.value.fetch(:delivery_intent).id
      assert_equal 1, callbacks.size
      assert_equal 1, delivery_intents.count
      assert_equal %w[duplicate issued], AuditLog.where(
        action: "identity.password_reset_requested",
        resource_id: @user.id
      ).map { |audit| audit.metadata.fetch("request_kind") }.sort
    end

    test "request after the cooldown rotates the token and supersedes the old worker" do
      first = nil
      second = nil
      callbacks = []
      ActiveRecord.stub(:after_all_transactions_commit, ->(&callback) { callbacks << callback }) do
        travel_to Time.zone.parse("2026-08-24 12:00:00") do
          first = ResetPassword.call(email: @user.email, ip_address: "203.0.113.10")
        end
        travel_to Time.zone.parse("2026-08-24 12:02:01") do
          second = ResetPassword.call(email: @user.email, ip_address: "203.0.113.10")
        end
      end

      refute_equal first.value.fetch(:reset_token), second.value.fetch(:reset_token)
      assert_equal 2, callbacks.size
      assert_equal 2, delivery_intents.count
      stale = SecurityRecoveryMailDelivery.deliver(first.value.fetch(:delivery_intent))
      assert_equal "skipped", stale.status
      assert_equal "recovery_token_superseded", stale.error_code
    end

    test "mail construction and transport errors escape to the durable retry lifecycle" do
      request = ResetPassword.call(email: @user.email, ip_address: "203.0.113.10")
      intent = request.value.fetch(:delivery_intent)

      Identity::Mailer.stub(:password_reset_email, ->(*) { raise KeyError, "template failure" }) do
        Operations::DispatchDurableIntentJob.perform_now(intent.id, 1, "maintenance")
      end

      projected = SecurityRecoveryMailDelivery.status(intent.reload)
      assert_equal "pending", projected.fetch(:status)
      assert_equal "retrying", projected.fetch(:durable_status)
      assert_equal "execution_failed", projected.fetch(:reason_code)
      assert_equal 1, projected.fetch(:attempt_count)
    end

    test "totp delivery decrypts only at execution and projects a sent status" do
      @user.setup_totp!
      @user.update!(totp_enabled: true)
      totp_secret = @user.totp_secret
      recovery_codes = Array(@user.recovery_codes)
      callbacks = []
      ActiveRecord.stub(:after_all_transactions_commit, ->(&callback) { callbacks << callback }) do
        assert_predicate RecoverTotp.call(email: @user.email), :success?
      end
      intent = delivery_intents.find_by!("arguments ->> 'purpose' = ?", "totp_recovery")
      token = @user.reload.totp_recovery_token
      audit = AuditLog.find_by!(
        action: "identity.totp_recovery_requested",
        resource_id: @user.id
      )

      assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
        Operations::DispatchDurableIntentJob.perform_now(intent.id, 1, "maintenance")
      end

      projected = SecurityRecoveryMailDelivery.status(intent.reload)
      assert_equal "sent", projected.fetch(:status)
      assert_equal "succeeded", projected.fetch(:durable_status)
      refute_equal token, @user.totp_recovery_token_ciphertext
      refute_includes intent.attributes.to_json, token
      refute_includes audit.attributes.to_json, token
      refute_includes audit.attributes.to_json, totp_secret
      recovery_codes.each { |code| refute_includes audit.attributes.to_json, code }
      refute_includes enqueued_jobs.to_json, token
      assert_equal 1, callbacks.size
    end

    test "status projection exposes only pending sent and failed" do
      intent = Struct.new(:id).new(1)
      snapshots = {
        "pending" => "pending",
        "running" => "pending",
        "retrying" => "pending",
        "succeeded" => "sent",
        "dead_lettered" => "failed",
        "skipped" => "failed"
      }

      snapshots.each do |durable_status, expected|
        snapshot = { status: durable_status, last_error_code: "delivery_error" }
        Operations::DurableEnqueueStatus.stub(:call, snapshot) do
          projected = SecurityRecoveryMailDelivery.status(intent)
          assert_equal expected, projected.fetch(:status)
          assert_equal durable_status, projected.fetch(:durable_status)
          assert_equal durable_status == "dead_lettered", projected.fetch(:retryable)
        end
      end
    end

    test "request audit failure rolls back the encrypted token and durable intent" do
      audit_failure = ServiceResult.failure(error: "audit_failed", code: "audit_failed")

      result = Administration::AuditLogger.stub(:call, audit_failure) do
        ResetPassword.call(email: @user.email, ip_address: "203.0.113.11")
      end

      assert_predicate result, :success?
      assert_nil result.value[:reset_token]
      @user.reload
      assert_nil @user.password_reset_token
      assert_nil @user.password_reset_token_digest
      assert_nil @user.password_reset_sent_at
      assert_empty delivery_intents
    end

    test "locked totp completion rejects a token superseded after candidate lookup" do
      @user.setup_totp!
      @user.update!(totp_enabled: true)
      first = nil
      travel_to Time.zone.parse("2026-08-24 13:00:00") do
        RecoverTotp.call(email: @user.email)
        first = @user.reload.totp_recovery_token
      end
      candidate = @user.reload
      travel_to Time.zone.parse("2026-08-24 13:02:01") do
        RecoverTotp.call(email: @user.email)
      end

      result = User.stub(:find_by, candidate) do
        RecoverTotp.call(token: first, password: "password123")
      end

      assert_predicate result, :failure?
      assert_equal "invalid_or_expired_totp_recovery_token", result.code
      assert @user.reload.totp_enabled?
      refute_equal first, @user.totp_recovery_token
    end

    test "totp completion audit failure restores the token state and sessions" do
      @user.setup_totp!
      @user.update!(totp_enabled: true)
      session = create_test_session(@user).value.fetch(:session)
      RecoverTotp.call(email: @user.email)
      token = @user.reload.totp_recovery_token
      original_audit = Administration::AuditLogger.method(:call)
      interceptor = lambda do |**arguments|
        if arguments[:action] == "identity.totp_recovered"
          ServiceResult.failure(error: "audit_failed", code: "audit_failed")
        else
          original_audit.call(**arguments)
        end
      end

      result = Administration::AuditLogger.stub(:call, interceptor) do
        RecoverTotp.call(token:, password: "password123")
      end

      assert_predicate result, :failure?
      @user.reload
      assert @user.totp_enabled?
      assert_equal token, @user.totp_recovery_token
      assert @user.totp_recovery_token_digest.present?
      refute_predicate session.reload, :revoked?
      refute AuditLog.exists?(action: "identity.totp_recovered", resource_id: @user.id)
    end

    test "account deactivation clears both encrypted recovery lifecycles" do
      ResetPassword.call(email: @user.email)
      @user.setup_totp!
      @user.update!(totp_enabled: true)
      RecoverTotp.call(email: @user.email)
      @user.reload
      assert @user.password_reset_token.present?
      assert @user.totp_recovery_token.present?

      @user.update!(status: :banned)

      @user.reload
      assert_nil @user.password_reset_token
      assert_nil @user.password_reset_token_digest
      assert_nil @user.password_reset_sent_at
      assert_nil @user.totp_recovery_token
      assert_nil @user.totp_recovery_token_digest
      assert_nil @user.totp_recovery_sent_at
    end

    test "email change invalidates both encrypted recovery lifecycles" do
      ResetPassword.call(email: @user.email)
      @user.setup_totp!
      @user.update!(totp_enabled: true)
      RecoverTotp.call(email: @user.email)
      @user.reload
      assert @user.password_reset_token.present?
      assert @user.totp_recovery_token.present?

      @user.update!(email: "changed-#{SecureRandom.hex(6)}@example.com")

      @user.reload
      assert_nil @user.password_reset_token
      assert_nil @user.password_reset_token_digest
      assert_nil @user.password_reset_sent_at
      assert_nil @user.totp_recovery_token
      assert_nil @user.totp_recovery_token_digest
      assert_nil @user.totp_recovery_sent_at
    end

    private

    def delivery_intents
      Operations::DurableEnqueueIntent.where(
        handler_key: SecurityRecoveryMailDelivery::HANDLER_KEY,
        source_id: @user.id
      )
    end
  end

  class TotpRecoveryConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    setup do
      @user = create_user
      @user.setup_totp!
      @token = SecureRandom.urlsafe_base64(32)
      @token_digest = Digest::SHA256.hexdigest(@token)
      @user.update!(
        totp_enabled: true,
        totp_recovery_token: @token,
        totp_recovery_token_digest: @token_digest,
        totp_recovery_sent_at: Time.current
      )
      @session = create_test_session(@user).value.fetch(:session)
    end

    teardown do
      AuditLog.where(actor_id: @user&.id).or(
        AuditLog.where(resource_type: "User", resource_id: @user&.id)
      ).delete_all
      Session.where(user_id: @user&.id).delete_all
      User.where(id: @user&.id).delete_all
    end

    test "two database connections can find the token but only one completes recovery" do
      candidates_ready = Queue.new
      release_candidates = Queue.new
      outcomes = Queue.new
      original_find_by = User.method(:find_by)
      find_interceptor = lambda do |*args, **kwargs|
        query = kwargs.presence || args.first
        candidate = original_find_by.call(*args, **kwargs)
        if query.is_a?(Hash) && query.key?(:totp_recovery_token_digest)
          candidates_ready << true
          release_candidates.pop
        end
        candidate
      end
      limiter_result = ServiceResult.success

      threads = User.stub(:find_by, find_interceptor) do
        Administration::RateLimiter.stub(:call, limiter_result) do
          2.times.map do
            Thread.new do
              ActiveRecord::Base.connection_pool.with_connection do
                outcomes << Identity::RecoverTotp.call(
                  token: @token,
                  password: "password123",
                  ip_address: "127.0.0.1"
                )
              rescue StandardError => error
                outcomes << error
              end
            end
          end.tap do |started_threads|
            Timeout.timeout(10) { 2.times { candidates_ready.pop } }
            2.times { release_candidates << true }
            started_threads.each do |thread|
              assert thread.join(10), "TOTP recovery thread did not finish"
            end
          end
        end
      end

      results = Timeout.timeout(10) { 2.times.map { outcomes.pop } }
      errors = results.grep(StandardError)
      raise errors.first if errors.any?

      assert_equal 1, results.count(&:success?)
      failures = results.select(&:failure?)
      assert_equal 1, failures.size
      assert_equal "invalid_or_expired_totp_recovery_token", failures.sole.code

      @user.reload
      refute @user.totp_enabled?
      assert_nil @user.totp_recovery_token
      assert_nil @user.totp_recovery_token_digest
      assert_predicate @session.reload, :revoked?
      audits = AuditLog.where(
        action: "identity.totp_recovered",
        resource_id: @user.id
      )
      assert_equal 1, audits.count
      refute_includes audits.sole.attributes.to_json, @token
      assert_equal 2, threads.size
    end
  end
end

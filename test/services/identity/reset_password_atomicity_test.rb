# frozen_string_literal: true

require "test_helper"
require "timeout"

module Identity
  class ResetPasswordAtomicityTest < ActiveSupport::TestCase
    test "audit failure rolls password token consumption and session revocation back" do
      user = create_user
      token = SecureRandom.urlsafe_base64(32)
      digest = Digest::SHA256.hexdigest(token)
      user.update!(
        password_reset_token_digest: digest,
        password_reset_sent_at: Time.current
      )
      session_record = create_test_session(user).value.fetch(:session)
      error = invalid_record(AuditLog)
      original_call = Administration::AuditLogger.method(:call)
      interceptor = lambda do |**arguments|
        if arguments[:action] == "identity.password_reset_completed"
          raise error
        end

        original_call.call(**arguments)
      end

      result = Administration::AuditLogger.stub(:call, interceptor) do
        Identity::ResetPassword.call(
          token:,
          new_password: "replacement456",
          ip_address: "127.0.0.1"
        )
      end

      assert_predicate result, :failure?
      user.reload
      assert user.authenticate("password123")
      refute user.authenticate("replacement456")
      assert_equal digest, user.password_reset_token_digest
      assert_nil session_record.reload.revoked_at
      refute AuditLog.exists?(
        action: "identity.password_reset_completed",
        resource_id: user.id
      )
    end

    private

    def invalid_record(model_class)
      record = model_class.new
      record.errors.add(:base, "injected failure")
      ActiveRecord::RecordInvalid.new(record)
    end
  end

  class ResetPasswordConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    setup do
      @user = create_user
      @token = SecureRandom.urlsafe_base64(32)
      @token_digest = Digest::SHA256.hexdigest(@token)
      @user.update!(
        password_reset_token_digest: @token_digest,
        password_reset_sent_at: Time.current
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

    test "two database connections can observe the candidate but only one consumes the token" do
      candidates_ready = Queue.new
      release_candidates = Queue.new
      outcomes = Queue.new
      original_find_by = User.method(:find_by)
      find_interceptor = lambda do |*args, **kwargs|
        query = kwargs.presence || args.first
        candidate = original_find_by.call(*args, **kwargs)
        if query.is_a?(Hash) && query.key?(:password_reset_token_digest)
          candidates_ready << true
          release_candidates.pop
        end
        candidate
      end
      limiter_result = ServiceResult.success

      threads = User.stub(:find_by, find_interceptor) do
        Administration::RateLimiter.stub(:call, limiter_result) do
          [ "replacement456", "replacement789" ].map do |password|
            Thread.new do
              ActiveRecord::Base.connection_pool.with_connection do
                outcomes << Identity::ResetPassword.call(
                  token: @token,
                  new_password: password,
                  ip_address: "127.0.0.1"
                )
              rescue StandardError => e
                outcomes << e
              end
            end
          end.tap do |started_threads|
            Timeout.timeout(10) { 2.times { candidates_ready.pop } }
            2.times { release_candidates << true }
            started_threads.each do |thread|
              assert thread.join(10), "password reset thread did not finish"
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
      assert_equal "invalid_or_expired_reset_token", failures.sole.code

      @user.reload
      refute @user.authenticate("password123")
      assert [ "replacement456", "replacement789" ].any? { |password| @user.authenticate(password) }
      assert_nil @user.password_reset_token_digest
      assert_predicate @session.reload, :revoked?
      audits = AuditLog.where(
        action: "identity.password_reset_completed",
        resource_id: @user.id
      )
      assert_equal 1, audits.count
      refute_includes audits.sole.attributes.to_json, @token
      refute_includes audits.sole.attributes.to_json, "replacement456"
      refute_includes audits.sole.attributes.to_json, "replacement789"
      assert_equal 2, threads.size
    end
  end
end

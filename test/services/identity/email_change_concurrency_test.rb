# frozen_string_literal: true

require "test_helper"

module Identity
  class EmailChangeConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    setup do
      @users = 2.times.map { create_user }
      @target = "contended-#{SecureRandom.hex(6)}@example.com"
    end

    teardown do
      request_ids = EmailChangeRequest.where(user_id: @users.map(&:id)).pluck(:id)
      intents = Operations::DurableEnqueueIntent.where(
        handler_key: EmailChangeDelivery::HANDLER_KEY,
        source_id: request_ids
      )
      with_mutable_durable_ledger do
        Operations::DurableEnqueueEvent.where(intent_id: intents.select(:id)).delete_all
        Operations::DurableEnqueueAttempt.where(intent_id: intents.select(:id)).delete_all
        intents.delete_all
      end
      AuditLog.where(actor_id: @users.map(&:id)).delete_all
      EmailChangeRequest.where(id: request_ids).delete_all
      Session.where(user_id: @users.map(&:id)).delete_all
      User.where(id: @users.map(&:id)).delete_all
    end

    test "two accounts cannot concurrently reserve the same replacement email" do
      ready = Queue.new
      gate = Queue.new
      results = Queue.new
      threads = @users.map do |user|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            gate.pop
            results << ChangeEmail.call(
              user: User.find(user.id),
              email: @target,
              password: "password123"
            )
          rescue StandardError => error
            results << error
          end
        end
      end

      2.times { ready.pop }
      2.times { gate << true }
      responses = 2.times.map { results.pop }
      threads.each(&:join)

      responses.each { |response| assert_instance_of ServiceResult, response }
      assert_equal 1, responses.count(&:success?)
      assert_equal 1, responses.count { |result| result.failure? && result.code == "email_not_available" }
      assert_equal 1, EmailChangeRequest.pending.where("LOWER(requested_email) = ?", @target).count
    end

    private

    def with_mutable_durable_ledger
      triggers = {
        operations_durable_enqueue_events: :operations_durable_events_immutable,
        operations_durable_enqueue_attempts: :operations_durable_attempts_immutable,
        operations_durable_enqueue_intents: :operations_durable_intents_immutable
      }
      connection = ApplicationRecord.connection
      disabled = []

      triggers.each do |table, trigger|
        connection.execute(<<~SQL.squish)
          ALTER TABLE #{connection.quote_table_name(table)}
          DISABLE TRIGGER #{connection.quote_column_name(trigger)}
        SQL
        disabled << [ table, trigger ]
      end

      yield
    ensure
      Array(disabled).reverse_each do |table, trigger|
        connection.execute(<<~SQL.squish)
          ALTER TABLE #{connection.quote_table_name(table)}
          ENABLE TRIGGER #{connection.quote_column_name(trigger)}
        SQL
      end
    end
  end
end

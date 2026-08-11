# frozen_string_literal: true

require "test_helper"
require "timeout"

module Operations
  class DurableEnqueueConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    teardown do
      Operations::DurableEnqueueEvent.connection.execute(<<~SQL)
        TRUNCATE TABLE
          operations_durable_enqueue_events,
          operations_durable_enqueue_attempts,
          operations_durable_enqueue_intents
        RESTART IDENTITY CASCADE
      SQL
    end

    test "duplicate jobs for one generation allow only one executor" do
      intent = nil
      ActiveRecord.stub(:after_all_transactions_commit, ->(&) { }) do
        Operations::DurableEnqueueIntent.transaction do
          intent = Operations::DurableEnqueue.record!(
            handler: "community.web_push",
            source_id: 91,
            dedupe_key: "test:concurrent:#{SecureRandom.uuid}"
          )
        end
      end

      entered = Queue.new
      release = Queue.new
      external_side_effects = 0
      side_effects_lock = Mutex.new
      executor = lambda do |_candidate, context:|
        _context = context
        side_effects_lock.synchronize { external_side_effects += 1 }
        entered << true
        release.pop
        Operations::DurableEnqueueResult.succeeded
      end

      threads = nil
      heartbeat_factory = lambda do |context:, interval:|
        Operations::DurableEnqueueHeartbeat.allocate.tap do |heartbeat|
          heartbeat.send(:initialize, context:, interval: 0.05)
        end
      end
      Operations::DurableEnqueueCatalog.stub(:execute, executor) do
        Operations::DurableEnqueueHeartbeat.stub(:new, heartbeat_factory) do
          started_at = Time.current
          entry = Operations::DurableEnqueueCatalog.entry(intent.handler_key)
          threads = 2.times.map do
            Thread.new do
              ActiveRecord::Base.connection_pool.with_connection do
                Operations::DispatchDurableIntentJob.perform_now(intent.id, 1, "maintenance")
              end
            end
          end

          Timeout.timeout(5) { entered.pop }
          recovery_at = started_at + entry.lease_seconds + 0.5.seconds
          travel_to(started_at + 1.second)
          Timeout.timeout(5) do
            Thread.pass until Operations::DurableEnqueueEvent.where(
              intent_id: intent.id,
              event_type: "lease_renewed"
            ).where("lease_expires_at > ?", recovery_at).exists?
          end
          travel_to(recovery_at)
          assert_no_enqueued_jobs do
            recovery = Operations::RecoverDurableEnqueue.call(
              intent_public_ids: [ intent.public_id ],
              limit: 1,
              now: Time.current
            )
            assert_predicate recovery, :success?
          end

          2.times { release << true }
          threads.each do |thread|
            assert thread.join(5), "durable enqueue worker thread did not stop"
            thread.value
          end
        end
      end

      assert_equal 1, external_side_effects
      assert_equal 1, Operations::DurableEnqueueAttempt.where(intent_id: intent.id).count
      assert_equal 1, Operations::DurableEnqueueEvent.where(
        intent_id: intent.id,
        event_type: "attempt_succeeded"
      ).count
    end
  end
end

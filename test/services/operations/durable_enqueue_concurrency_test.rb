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
      workers_ready = Queue.new
      start_workers = Queue.new
      heartbeat_ready = Queue.new
      heartbeat_results = Queue.new
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
        heartbeat = Object.new
        heartbeat_command = Queue.new
        heartbeat_thread = nil
        heartbeat.define_singleton_method(:start) do
          heartbeat_thread = Thread.new do
            Thread.current.report_on_exception = false
            Rails.application.executor.wrap do
              heartbeat_ready << heartbeat_command
              if heartbeat_command.pop == :tick
                heartbeat_results << context.heartbeat!
              end
            end
          end
          heartbeat
        end
        heartbeat.define_singleton_method(:stop) do
          if heartbeat_thread
            heartbeat_command << :stop if heartbeat_thread.alive?
            unless heartbeat_thread.join(5)
              raise Timeout::Error, "durable enqueue heartbeat thread did not stop"
            end
            heartbeat_thread.value
          end
        end
        heartbeat
      end
      Operations::DurableEnqueueCatalog.stub(:execute, executor) do
        Operations::DurableEnqueueHeartbeat.stub(:new, heartbeat_factory) do
          threads = 2.times.map do
            Thread.new do
              workers_ready << true
              start_workers.pop
              ActiveRecord::Base.connection_pool.with_connection do
                Operations::DispatchDurableIntentJob.perform_now(intent.id, 1, "maintenance")
              end
            end
          end

          workers_released = false
          heartbeat_command = nil
          begin
            2.times { Timeout.timeout(5) { workers_ready.pop } }
            2.times { start_workers << true }
            workers_released = true

            heartbeat_command = Timeout.timeout(5) { heartbeat_ready.pop }
            Timeout.timeout(5) { entered.pop }
            attempt = Operations::DurableEnqueueAttempt.find_by!(intent_id: intent.id)
            original_lease_expires_at = attempt.lease_expires_at
            lease_duration = original_lease_expires_at - attempt.started_at
            renewal_at = attempt.started_at + (lease_duration / 2)
            recovery_at = original_lease_expires_at + (lease_duration / 4)
            assert_operator recovery_at, :>, original_lease_expires_at
            travel_to(renewal_at, with_usec: true)
            heartbeat_command << :tick
            heartbeat_result = Timeout.timeout(5) { heartbeat_results.pop }
            assert_predicate heartbeat_result, :success?
            assert_equal true, heartbeat_result.value.fetch(:renewed)
            assert Operations::DurableEnqueueEvent.where(
              intent_id: intent.id,
              event_type: "lease_renewed"
            ).where("lease_expires_at > ?", recovery_at).exists?

            travel_to(recovery_at, with_usec: true)
            assert_no_enqueued_jobs do
              recovery = Operations::RecoverDurableEnqueue.call(
                intent_public_ids: [ intent.public_id ],
                limit: 1,
                now: Time.current
              )
              assert_predicate recovery, :success?
            end
          ensure
            2.times { start_workers << true } unless workers_released
            heartbeat_command << :stop if heartbeat_command
            2.times { release << true }
            joined_workers = threads.map do |thread|
              [ thread, thread.join(5) ]
            end
            joined_workers.each do |_thread, joined|
              assert joined, "durable enqueue worker thread did not stop"
            end
            joined_workers.each { |thread, _joined| thread.value }
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

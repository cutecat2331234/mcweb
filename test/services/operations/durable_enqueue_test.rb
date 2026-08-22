# frozen_string_literal: true

require "test_helper"

module Operations
  class DurableEnqueueTest < ActiveSupport::TestCase
    setup do
      clear_enqueued_jobs
      clear_performed_jobs
      Operations::DurableEnqueueEvent.connection.execute(<<~SQL)
        TRUNCATE TABLE
          operations_durable_enqueue_events,
          operations_durable_enqueue_attempts,
          operations_durable_enqueue_intents
        RESTART IDENTITY CASCADE
      SQL
      @callbacks = []
    end

    test "registry is frozen and never accepts a caller selected queue or arbitrary arguments" do
      registry = Operations::DurableEnqueueRegistry.new
      registry.register(
        key: "test.safe_handler",
        source_kind: "safe_source",
        queue: "maintenance",
        replay_contract: "idempotent",
        argument_schema: {
          "record_id" => { type: "integer", required: true, minimum: 1 }
        }
      ) { Operations::DurableEnqueueResult.succeeded }
      entry = registry.entry("test.safe_handler")

      assert_equal({ "record_id" => 7 }, registry.normalize_arguments(entry, record_id: "7"))
      assert_raises(ArgumentError) do
        registry.normalize_arguments(entry, record_id: 7, job_class: "Kernel")
      end
      assert_raises(ArgumentError) do
        registry.register(
          key: "test.unsafe_queue",
          source_kind: "safe_source",
          queue: "caller_selected",
          replay_contract: "idempotent"
        ) { Operations::DurableEnqueueResult.succeeded }
      end

      registry.freeze!
      assert_predicate registry, :frozen?
      assert_raises(FrozenError) do
        registry.register(
          key: "test.late_handler",
          source_kind: "safe_source",
          queue: "default",
          replay_contract: "idempotent"
        ) { Operations::DurableEnqueueResult.succeeded }
      end

      assert_predicate Operations::DurableEnqueueCatalog, :registry_frozen?
      assert_raises(FrozenError) do
        Mcweb::OperationsDurableEnqueueRegistrarConfig.register!(
          Rails.application.config.x,
          ->(_) { }
        )
      end
    end

    test "registry defaults and validates handler-owned manual reopen permissions" do
      registry = Operations::DurableEnqueueRegistry.new
      default_entry = registry.register(
        key: "test.default_reopen",
        source_kind: "safe_source",
        queue: "maintenance",
        replay_contract: "idempotent"
      ) { Operations::DurableEnqueueResult.succeeded }
      custom_entry = registry.register(
        key: "test.custom_reopen",
        source_kind: "safe_source",
        queue: "maintenance",
        replay_contract: "idempotent",
        manual_reopen_permission: "product.notifications.retry"
      ) { Operations::DurableEnqueueResult.succeeded }

      assert_equal "system.jobs.manage", default_entry.manual_reopen_permission
      assert_equal "product.notifications.retry", custom_entry.manual_reopen_permission
      assert_raises(ArgumentError) do
        registry.register(
          key: "test.invalid_reopen",
          source_kind: "safe_source",
          queue: "maintenance",
          replay_contract: "idempotent",
          manual_reopen_permission: "Product Notifications Retry"
        ) { Operations::DurableEnqueueResult.succeeded }
      end
    end

    test "record requires a business transaction and rejects conflicting replays" do
      connection = ApplicationRecord.connection
      connection.stub(:transaction_open?, false) do
        assert_raises(Operations::DurableEnqueue::TransactionRequired) do
          Operations::DurableEnqueue.record!(
            handler: "community.web_push",
            source_id: 1,
            dedupe_key: "notification:1"
          )
        end
      end

      intent = create_intent(source_id: 41, dedupe_key: "test:record:41")
      replay = nil
      suppress_after_commit do
        Operations::DurableEnqueueIntent.transaction do
          replay = Operations::DurableEnqueue.record!(
            handler: "community.web_push",
            source_id: 41,
            dedupe_key: "test:record:41"
          )
        end
      end
      assert_equal intent, replay
      assert_equal 1, intent.events.where(event_type: "recorded").count

      assert_raises(Operations::DurableEnqueue::IdempotencyConflict) do
        suppress_after_commit do
          Operations::DurableEnqueueIntent.transaction do
            Operations::DurableEnqueue.record!(
              handler: "community.web_push",
              source_id: 42,
              dedupe_key: "test:record:41"
            )
          end
        end
      end
    end

    test "notification and durable intent commit and roll back together" do
      user = create_user
      notification = nil

      assert_no_enqueued_jobs do
        assert_no_difference -> { Notification.count } do
          assert_no_difference -> { Operations::DurableEnqueueIntent.count } do
            Notification.transaction(requires_new: true) do
              Notification.notify!(
                user:,
                notification_type: "forum.mention",
                title: "Rolled back"
              )
              raise ActiveRecord::Rollback
            end
          end
        end
      end

      collect_after_commit do
        notification = Notification.notify!(
          user:,
          notification_type: "forum.mention",
          title: "Durable notification",
          body: "Private body must not enter the intent"
        )
      end

      intent = Operations::DurableEnqueueIntent.find_by!(
        handler_key: "community.web_push",
        source_id: notification.id
      )
      assert_equal "notification", intent.source_kind
      assert_equal "default", intent.queue_name
      assert_empty intent.arguments
      refute_includes intent.attributes.to_json, "Private body"
      assert_equal 1, @callbacks.length

      assert_enqueued_with(
        job: Operations::DispatchDurableIntentJob,
        args: [ intent.id, 1, "after_commit" ],
        queue: "default"
      ) do
        @callbacks.sole.call
      end
      assert_equal "enqueue_succeeded", intent.events.order(:sequence).last.event_type
    end

    test "enqueue failure and a successfully enqueued but lost job are both recoverable" do
      failed_intent = create_intent(source_id: 51, dedupe_key: "test:enqueue-failed:51")
      callback = @callbacks.pop
      Operations::DispatchDurableIntentJob.stub(:set, ->(**) { raise IOError, "queue unavailable" }) do
        assert_predicate callback.call, :failure?
      end
      failed_event = failed_intent.events.order(:sequence).last
      assert_equal "enqueue_failed", failed_event.event_type
      assert_equal "enqueue_failed", failed_event.error_code

      failed_recovery_at = failed_event.occurred_at +
        Operations::DurableEnqueueCatalog.entry(failed_intent.handler_key).enqueue_stale_seconds + 1.second
      assert_enqueued_with(job: Operations::DispatchDurableIntentJob) do
        result = Operations::RecoverDurableEnqueue.call(now: failed_recovery_at)
        assert_predicate result, :success?
        assert_equal 1, result.value.fetch(:enqueued_count)
      end

      clear_enqueued_jobs
      lost_intent = create_intent(source_id: 52, dedupe_key: "test:enqueue-lost:52")
      @callbacks.pop.call
      enqueue_event = lost_intent.events.order(:sequence).last
      assert_equal "enqueue_succeeded", enqueue_event.event_type
      clear_enqueued_jobs # Simulate an adapter accepting and then losing the job.

      assert_no_enqueued_jobs do
        duplicate = Operations::DurableEnqueueDispatcher.call(
          intent_id: lost_intent.id,
          generation: 1,
          trigger: "maintenance",
          now: enqueue_event.occurred_at + 10.seconds
        )
        assert_predicate duplicate, :success?
        assert duplicate.value.fetch(:skipped)
      end

      lost_recovery_at = enqueue_event.occurred_at +
        Operations::DurableEnqueueCatalog.entry(lost_intent.handler_key).enqueue_stale_seconds + 1.second
      assert_enqueued_with(job: Operations::DispatchDurableIntentJob) do
        result = Operations::RecoverDurableEnqueue.call(now: lost_recovery_at)
        assert_predicate result, :success?
        assert_operator result.value.fetch(:enqueued_count), :>=, 1
      end
      assert_operator lost_intent.events.where(event_type: "enqueue_succeeded").count, :>=, 2
    end

    test "source missing becomes a terminal skipped outcome and cannot be manually reopened" do
      intent = create_intent(source_id: 9_999_999, dedupe_key: "test:missing-source")

      Operations::DispatchDurableIntentJob.perform_now(intent.id, 1, "maintenance")

      state = Operations::DurableEnqueueLedger.state(intent)
      assert_predicate state, :terminal?
      assert_equal "skipped", state.status
      skipped = intent.events.find_by!(event_type: "attempt_skipped")
      assert_equal "source_missing", skipped.error_code
      assert_equal 1, intent.attempts.count

      actor = create_user(account_type: "owner")
      grant_permission(actor, "system.jobs.manage")
      result = Operations::RecoverDurableEnqueue.call(
        intent_public_ids: [ intent.public_id ],
        trigger: "manual",
        actor:,
        reopen: true,
        reason: "Source was checked"
      )
      assert_predicate result, :success?
      assert_equal 1, result.value.fetch(:skipped_count)
      assert_not intent.events.exists?(event_type: "reopened")
    end

    test "expired worker lease is recorded once and a new claim uses the next attempt number" do
      intent = create_intent(source_id: 59, dedupe_key: "test:expired-lease:59")
      started_at = 3.minutes.ago
      attempt = nil
      Operations::DurableEnqueueLedger.with_locked_intent(intent) do |state|
        attempt = intent.attempts.create!(
          attempt_number: 1,
          generation: 1,
          lease_token: SecureRandom.uuid,
          job_id: SecureRandom.uuid,
          trigger: "maintenance",
          started_at:,
          lease_expires_at: started_at + 1.minute
        )
        Operations::DurableEnqueueLedger.append_locked!(
          intent:,
          state:,
          event_type: "attempt_started",
          generation: 1,
          attempt:,
          metadata: { attempt_number: 1, trigger: "maintenance" },
          occurred_at: started_at
        )
      end

      assert_enqueued_with(job: Operations::DispatchDurableIntentJob) do
        result = Operations::RecoverDurableEnqueue.call(now: Time.current)
        assert_predicate result, :success?
        assert_equal 1, result.value.fetch(:enqueued_count)
      end
      assert_equal 1, intent.events.where(event_type: "lease_expired").count
      assert_equal attempt, intent.events.find_by!(event_type: "lease_expired").attempt

      clear_enqueued_jobs
      Operations::DurableEnqueueCatalog.stub(
        :execute,
        ->(_, context:) {
          assert_equal intent.public_id, context.intent_public_id
          Operations::DurableEnqueueResult.succeeded
        }
      ) do
        Operations::DispatchDurableIntentJob.perform_now(intent.id, 1, "maintenance")
      end
      assert_equal [ 1, 2 ], intent.attempts.order(:attempt_number).pluck(:attempt_number)
      assert_equal 1, intent.events.where(event_type: "lease_expired").count
      assert_equal "succeeded", Operations::DurableEnqueueLedger.state(intent).status
    end

    test "lease renewal beyond the original lease prevents a second executor" do
      intent = create_intent(source_id: 60, dedupe_key: "test:renewed-lease:60")
      now = Time.current
      attempt = nil
      Operations::DurableEnqueueLedger.with_locked_intent(intent) do |state|
        attempt = intent.attempts.create!(
          attempt_number: 1,
          generation: 1,
          lease_token: SecureRandom.uuid,
          job_id: SecureRandom.uuid,
          trigger: "maintenance",
          started_at: now - 10.minutes,
          lease_expires_at: now - 1.minute
        )
        started = Operations::DurableEnqueueLedger.append_locked!(
          intent:,
          state:,
          event_type: "attempt_started",
          generation: 1,
          attempt:,
          metadata: { attempt_number: 1, trigger: "maintenance" },
          occurred_at: now - 10.minutes
        )
        intent.association(:events).reset
        current = Operations::DurableEnqueueLedger.state(intent)
        assert_equal started.attempt_id, current.active_attempt.id
        Operations::DurableEnqueueLedger.append_locked!(
          intent:,
          state: current,
          event_type: "lease_renewed",
          generation: 1,
          attempt:,
          metadata: { attempt_number: 1 },
          occurred_at: now - 2.minutes,
          lease_expires_at: now + 3.minutes
        )
      end

      executor_calls = 0
      Operations::DurableEnqueueCatalog.stub(
        :execute,
        ->(_, context:) {
          executor_calls += 1
          assert_predicate context.heartbeat!, :success?
          Operations::DurableEnqueueResult.succeeded
        }
      ) do
        travel_to(now) do
          Operations::DispatchDurableIntentJob.perform_now(intent.id, 1, "maintenance")
        end
      end

      assert_equal 0, executor_calls
      assert_equal 1, intent.attempts.count
      assert_in_delta(
        (now + 3.minutes).to_f,
        Operations::DurableEnqueueLedger.state(intent).active_lease_expires_at.to_f,
        1e-5
      )
    end

    test "keyset recovery scans past fresh rows until it fills the due limit" do
      5.times do |index|
        create_intent(source_id: 100 + index, dedupe_key: "test:keyset:fresh:#{index}")
      end
      due = create_intent(
        source_id: 199,
        dedupe_key: "test:keyset:due",
        requested_at: 10.minutes.ago
      )

      assert_enqueued_jobs 1, only: Operations::DispatchDurableIntentJob do
        result = Operations::RecoverDurableEnqueue.call(limit: 1, now: Time.current)
        assert_predicate result, :success?
        assert_equal 1, result.value.fetch(:candidate_count)
        assert_operator result.value.fetch(:scanned_count), :>=, 6
        assert_equal [ due.public_id ], result.value.fetch(:intent_public_ids)
      end
    end

    test "recovery reports partial work and fails when every due enqueue fails" do
      first = create_intent(
        source_id: 201,
        dedupe_key: "test:partial:first",
        requested_at: 10.minutes.ago
      )
      second = create_intent(
        source_id: 202,
        dedupe_key: "test:partial:second",
        requested_at: 10.minutes.ago
      )
      dispatcher = lambda do |intent_id:, **|
        if intent_id == first.id
          ServiceResult.success(enqueued: true)
        else
          ServiceResult.failure(error: "enqueue failed", code: "enqueue_failed")
        end
      end

      Operations::DurableEnqueueDispatcher.stub(:call, dispatcher) do
        partial = Operations::RecoverDurableEnqueue.call(limit: 2, now: Time.current)
        assert_predicate partial, :success?
        assert_equal true, partial.value.fetch(:partial)
        assert_equal 1, partial.value.fetch(:enqueued_count)
        assert_equal 1, partial.value.fetch(:failed_count)
        assert_equal [ first.public_id ], partial.value.fetch(:intent_public_ids)
      end

      all_failed_dispatcher = lambda do |**|
        ServiceResult.failure(error: "enqueue failed", code: "enqueue_failed")
      end
      Operations::DurableEnqueueDispatcher.stub(:call, all_failed_dispatcher) do
        failed = Operations::RecoverDurableEnqueue.call(
          limit: 2,
          intent_public_ids: [ first.public_id, second.public_id ],
          now: Time.current
        )
        assert_predicate failed, :failure?
        assert_equal false, failed.value.fetch(:partial)
        assert_equal 0, failed.value.fetch(:enqueued_count)
        assert_equal 2, failed.value.fetch(:failed_count)
      end
    end

    test "exhausted intent can be explicitly reopened into a new generation only" do
      intent = create_intent(source_id: 61, dedupe_key: "test:dead-letter:61")
      core_entry = Operations::DurableEnqueueCatalog.entry(intent.handler_key)
      entry = Operations::DurableEnqueueRegistry::Entry.new(
        **core_entry.to_h.merge(max_attempts: 2, retry_delays: [ 1 ])
      )
      failure = lambda do |_intent, context:|
        assert_equal "at_least_once", context.replay_contract
        raise Operations::DurableEnqueueCatalog::ExecutionError, "simulated_failure"
      end
      started_at = Time.current

      Operations::DurableEnqueueCatalog.stub(:entry, ->(_) { entry }) do
        Operations::DurableEnqueueCatalog.stub(:execute, failure) do
          travel_to(started_at) do
            Operations::DispatchDurableIntentJob.perform_now(intent.id, 1, "maintenance")
          end
          travel_to(started_at + 2.seconds) do
            Operations::DispatchDurableIntentJob.perform_now(intent.id, 1, "maintenance")
          end
        end
      end

      state = Operations::DurableEnqueueLedger.state(intent)
      assert_predicate state, :terminal?
      assert_equal "dead_lettered", state.status
      assert_equal 2, state.attempt_count

      assert_raises(ActiveRecord::StatementInvalid) do
        Operations::DurableEnqueueEvent.transaction(requires_new: true) do
          next_sequence = intent.events.maximum(:sequence) + 1
          Operations::DurableEnqueueEvent.connection.execute(<<~SQL)
            INSERT INTO operations_durable_enqueue_events
              (intent_id, sequence, generation, event_type, metadata, occurred_at, created_at, updated_at)
            VALUES
              (#{intent.id}, #{next_sequence}, 2, 'reopened', '{}', NOW(), NOW(), NOW())
          SQL
        end
      end

      actor = create_user(account_type: "owner")
      grant_permission(actor, "system.jobs.manage")
      assert_enqueued_with(job: Operations::DispatchDurableIntentJob, args: [ intent.id, 2, "manual" ]) do
        reopened = Operations::RecoverDurableEnqueue.call(
          intent_public_ids: [ intent.public_id ],
          trigger: "manual",
          actor:,
          reopen: true,
          reason: "Provider health was independently verified"
        )
        assert_predicate reopened, :success?
        assert_equal 1, reopened.value.fetch(:enqueued_count)
      end

      reopen_event = intent.events.find_by!(event_type: "reopened")
      assert_equal 2, reopen_event.generation
      assert_equal actor.id, reopen_event.metadata.fetch("actor_id")
      assert_equal "Provider health was independently verified", reopen_event.metadata.fetch("reason")
      audit = AuditLog.for_resource(intent).find_by!(action: "operations.durable_enqueue.reopened")
      assert_equal intent.public_id, audit.metadata.fetch("intent_public_id")
      refute audit.metadata.key?("source_id")
      refute audit.metadata.key?("arguments")

      Operations::DispatchDurableIntentJob.perform_now(intent.id, 1, "maintenance")
      assert_equal 2, intent.attempts.where(generation: 1).count

      clear_enqueued_jobs
      Operations::DurableEnqueueCatalog.stub(
        :execute,
        ->(_, context:) {
          assert_equal "operations-durable:#{intent.public_id}", context.idempotency_key
          Operations::DurableEnqueueResult.succeeded
        }
      ) do
        Operations::DispatchDurableIntentJob.perform_now(intent.id, 2, "manual")
      end
      final_state = Operations::DurableEnqueueLedger.state(intent)
      assert_predicate final_state, :terminal?
      assert_equal "succeeded", final_state.status
      assert_equal 1, final_state.attempt_count
      assert_equal [ 1, 2, 3 ], intent.attempts.order(:attempt_number).pluck(:attempt_number)
      assert_equal [ 1, 1, 2 ], intent.attempts.order(:attempt_number).pluck(:generation)

      rejected = Operations::RecoverDurableEnqueue.call(
        intent_public_ids: [ intent.public_id ],
        trigger: "manual",
        actor:,
        reopen: true,
        reason: "Completed work must remain completed"
      )
      assert_predicate rejected, :success?
      assert_equal 1, rejected.value.fetch(:skipped_count)
      assert_equal 1, intent.events.where(event_type: "reopened").count
    end

    test "handler-owned permission reopens only its registered durable intent" do
      entry = custom_reopen_entry(
        key: "test.product_notification",
        permission: "product.notifications.retry"
      )
      intent = create_intent_for_entry(
        entry,
        source_id: 62,
        dedupe_key: "test:custom-reopen:62"
      )
      dead_letter_intent!(intent)
      actor = create_user
      grant_permission(actor, "product.notifications.retry")

      Operations::DurableEnqueueCatalog.stub(:entry, ->(_) { entry }) do
        assert_enqueued_with(
          job: Operations::DispatchDurableIntentJob,
          args: [ intent.id, 2, "manual" ]
        ) do
          result = Operations::RecoverDurableEnqueue.call(
            intent_public_ids: [ intent.public_id ],
            trigger: "manual",
            actor:,
            reopen: true,
            reason: "Product operator approved a bounded recovery"
          )

          assert_predicate result, :success?
          assert_equal 1, result.value.fetch(:enqueued_count)
        end
      end

      assert_equal 1, intent.events.where(event_type: "reopened").count
      assert AuditLog.for_resource(intent).exists?(action: "operations.durable_enqueue.reopened")
      refute actor.permission?("system.jobs.manage")
    end

    test "mixed reopen selection is rejected atomically before any side effect" do
      entries = {
        "test.product_notification" => custom_reopen_entry(
          key: "test.product_notification",
          permission: "product.notifications.retry"
        ),
        "test.global_notification" => custom_reopen_entry(
          key: "test.global_notification",
          permission: "system.jobs.manage"
        )
      }
      allowed = create_intent_for_entry(
        entries.fetch("test.product_notification"),
        source_id: 63,
        dedupe_key: "test:mixed-reopen:allowed"
      )
      protected = create_intent_for_entry(
        entries.fetch("test.global_notification"),
        source_id: 64,
        dedupe_key: "test:mixed-reopen:protected"
      )
      dead_letter_intent!(allowed)
      dead_letter_intent!(protected)
      actor = create_user
      grant_permission(actor, "product.notifications.retry")

      Operations::DurableEnqueueCatalog.stub(:entry, ->(key) { entries[key] }) do
        assert_no_enqueued_jobs do
          assert_no_difference -> { Operations::DurableEnqueueEvent.count } do
            assert_no_difference -> { AuditLog.count } do
              result = Operations::RecoverDurableEnqueue.call(
                intent_public_ids: [ allowed.public_id, protected.public_id ],
                trigger: "manual",
                actor:,
                reopen: true,
                reason: "This mixed selection must not partially reopen"
              )

              assert_predicate result, :failure?
              assert_equal "durable_enqueue_reopen_forbidden", result.code
            end
          end
        end
      end

      refute allowed.events.exists?(event_type: "reopened")
      refute protected.events.exists?(event_type: "reopened")
    end

    test "unknown reopen selection is rejected without audit or enqueue" do
      actor = create_user
      grant_permission(actor, "system.jobs.manage")

      assert_no_enqueued_jobs do
        assert_no_difference -> { Operations::DurableEnqueueEvent.count } do
          assert_no_difference -> { AuditLog.count } do
            result = Operations::RecoverDurableEnqueue.call(
              intent_public_ids: [ SecureRandom.uuid ],
              trigger: "manual",
              actor:,
              reopen: true,
              reason: "The selected operation must exist"
            )

            assert_predicate result, :failure?
            assert_equal "durable_enqueue_reopen_selection_invalid", result.code
          end
        end
      end
    end

    test "status snapshot and manual task schemas expose no source or payload" do
      intent = create_intent(source_id: 71, dedupe_key: "test:status:71")
      snapshot = Operations::DurableEnqueueStatus.call(intent)

      assert_equal intent.public_id, snapshot.fetch(:public_id)
      assert_equal "community.web_push", snapshot.fetch(:handler_key)
      assert_equal "at_least_once", snapshot.fetch(:replay_contract)
      refute snapshot.key?(:source_id)
      refute snapshot.key?(:dedupe_key)
      refute snapshot.key?(:arguments)

      retry_task = Operations::ManualTaskCatalog.entry("operations.durable_enqueue.retry_selected")
      normalized = Operations::ManualTaskCatalog.normalize_arguments(
        retry_task,
        intent_public_ids: intent.public_id,
        reason: "Explicit recovery approval"
      )
      assert_equal [ intent.public_id ], normalized.fetch("intent_public_ids")
      assert_equal "Explicit recovery approval", normalized.fetch("reason")
      assert_raises(Operations::ManualTaskCatalog::InvalidTask) do
        Operations::ManualTaskCatalog.normalize_arguments(
          retry_task,
          intent_public_ids: intent.public_id,
          reason: "x" * 501
        )
      end
    end

    test "lease expiry is attempt-bound and cannot precede the effective renewed lease" do
      now = Time.current
      intent = create_intent(source_id: 83, dedupe_key: "test:lease-expiry-contract:83")
      attempt = intent.attempts.create!(
        attempt_number: 1,
        generation: 1,
        lease_token: SecureRandom.uuid,
        job_id: SecureRandom.uuid,
        trigger: "maintenance",
        started_at: now,
        lease_expires_at: now + 1.minute
      )
      Operations::DurableEnqueueLedger.append!(
        intent:,
        event_type: "attempt_started",
        generation: 1,
        attempt:,
        metadata: { attempt_number: 1, trigger: "maintenance" },
        occurred_at: now
      )
      assert_raises(ActiveRecord::StatementInvalid) do
        intent.attempts.create!(
          attempt_number: 2,
          generation: 1,
          lease_token: SecureRandom.uuid,
          job_id: SecureRandom.uuid,
          trigger: "maintenance",
          started_at: now + 1.second,
          lease_expires_at: now + 2.minutes
        )
      end
      renewed_until = now + 3.minutes
      Operations::DurableEnqueueLedger.append!(
        intent:,
        event_type: "lease_renewed",
        generation: 1,
        attempt:,
        metadata: { attempt_number: 1 },
        occurred_at: now + 30.seconds,
        lease_expires_at: renewed_until
      )

      assert_raises(ActiveRecord::RecordInvalid) do
        Operations::DurableEnqueueLedger.append!(
          intent:,
          event_type: "lease_expired",
          generation: 1,
          attempt:,
          metadata: { attempt_number: 1 },
          occurred_at: renewed_until - 1.second
        )
      end
      assert_raises(ActiveRecord::StatementInvalid) do
        Operations::DurableEnqueueEvent.transaction(requires_new: true) do
          insert_native_lease_expired!(
            intent:,
            attempt:,
            occurred_at: renewed_until - 1.second
          )
        end
      end

      other_intent = create_intent(source_id: 84, dedupe_key: "test:lease-expiry-contract:84")
      other_attempt = other_intent.attempts.create!(
        attempt_number: 1,
        generation: 1,
        lease_token: SecureRandom.uuid,
        job_id: SecureRandom.uuid,
        trigger: "maintenance",
        started_at: now,
        lease_expires_at: now + 1.minute
      )
      Operations::DurableEnqueueLedger.append!(
        intent: other_intent,
        event_type: "attempt_started",
        generation: 1,
        attempt: other_attempt,
        metadata: { attempt_number: 1, trigger: "maintenance" },
        occurred_at: now
      )
      assert_raises(ActiveRecord::StatementInvalid) do
        Operations::DurableEnqueueEvent.transaction(requires_new: true) do
          insert_native_lease_expired!(
            intent:,
            attempt: other_attempt,
            occurred_at: renewed_until
          )
        end
      end

      expired = Operations::DurableEnqueueLedger.append!(
        intent:,
        event_type: "lease_expired",
        generation: 1,
        attempt:,
        metadata: { attempt_number: 1 },
        occurred_at: renewed_until
      )
      assert_equal attempt, expired.attempt
      job = Operations::DispatchDurableIntentJob.new
      entry = Operations::DurableEnqueueCatalog.entry(intent.handler_key)
      assert_no_difference -> { intent.events.count } do
        job.send(
          :finish,
          intent,
          attempt:,
          result: Operations::DurableEnqueueResult.succeeded
        )
      end
      assert_no_difference -> { intent.events.count } do
        job.send(
          :fail_attempt,
          intent,
          attempt:,
          entry:,
          error_code: "execution_failed"
        )
      end
      assert_raises(ActiveRecord::StatementInvalid) do
        Operations::DurableEnqueueEvent.transaction(requires_new: true) do
          insert_native_lease_expired!(intent:, attempt:, occurred_at: renewed_until + 1.second)
        end
      end
    end

    test "ledger tables reject update and delete bypasses" do
      intent = create_intent(source_id: 81, dedupe_key: "test:immutable:81")
      event = intent.events.find_by!(event_type: "recorded")
      attempt = intent.attempts.create!(
        attempt_number: 1,
        generation: 1,
        lease_token: SecureRandom.uuid,
        job_id: SecureRandom.uuid,
        trigger: "maintenance",
        started_at: Time.current,
        lease_expires_at: 5.minutes.from_now
      )

      assert_raises(ActiveRecord::StatementInvalid) do
        Operations::DurableEnqueueEvent.transaction(requires_new: true) do
          Operations::DurableEnqueueEvent.connection.execute(<<~SQL)
            INSERT INTO operations_durable_enqueue_events
              (intent_id, attempt_id, sequence, generation, event_type, metadata,
               occurred_at, created_at, updated_at)
            VALUES
              (#{intent.id}, #{attempt.id}, 2, 1, 'attempt_succeeded', '{}', NOW(), NOW(), NOW())
          SQL
        end
      end

      Operations::DurableEnqueueLedger.with_locked_intent(intent) do |state|
        Operations::DurableEnqueueLedger.append_locked!(
          intent:,
          state:,
          event_type: "attempt_started",
          generation: 1,
          attempt:,
          metadata: { attempt_number: 1, trigger: "maintenance" }
        )
      end
      assert_raises(ActiveRecord::StatementInvalid) do
        Operations::DurableEnqueueEvent.transaction(requires_new: true) do
          Operations::DurableEnqueueEvent.connection.execute(<<~SQL)
            INSERT INTO operations_durable_enqueue_events
              (intent_id, attempt_id, sequence, generation, event_type, metadata,
               occurred_at, created_at, updated_at)
            VALUES
              (#{intent.id}, #{attempt.id}, 3, 1, 'attempt_started', '{}', NOW(), NOW(), NOW())
          SQL
        end
      end

      assert_raises(ActiveRecord::StatementInvalid) do
        Operations::DurableEnqueueEvent.transaction(requires_new: true) do
          Operations::DurableEnqueueEvent.connection.execute(<<~SQL)
            UPDATE operations_durable_enqueue_events
            SET event_type = 'enqueue_succeeded'
            WHERE id = #{event.id}
          SQL
        end
      end
      assert_raises(ActiveRecord::StatementInvalid) do
        Operations::DurableEnqueueIntent.transaction(requires_new: true) do
          Operations::DurableEnqueueIntent.connection.execute(<<~SQL)
            DELETE FROM operations_durable_enqueue_intents
            WHERE id = #{intent.id}
          SQL
        end
      end
      assert_raises(ActiveRecord::StatementInvalid) do
        Operations::DurableEnqueueEvent.transaction(requires_new: true) do
          Operations::DurableEnqueueEvent.connection.execute(<<~SQL)
            INSERT INTO operations_durable_enqueue_events
              (intent_id, sequence, generation, event_type, metadata, occurred_at, created_at, updated_at)
            VALUES
              (#{intent.id}, 99, 1, 'enqueue_requested', '{}', NOW(), NOW(), NOW())
          SQL
        end
      end
    end

    test "maintenance schedule registers durable enqueue recovery" do
      schedule = YAML.safe_load_file(Rails.root.join("config/sidekiq_cron.yml"))
      entry = schedule.fetch("recover_durable_enqueue")

      assert_equal "* * * * *", entry.fetch("cron")
      assert_equal "Operations::RecoverDurableEnqueueJob", entry.fetch("class")
      assert_equal "maintenance", entry.fetch("queue")
      assert_equal true, entry.fetch("active_job")
    end

  test "heartbeat accepts only finite positive intervals" do
    context = Object.new

    heartbeat = Operations::DurableEnqueueHeartbeat.new(context:, interval: 0.05)
    assert_instance_of Operations::DurableEnqueueHeartbeat, heartbeat
    assert_in_delta 0.05, heartbeat.instance_variable_get(:@interval), 0.0001

    [ 0, -1, Float::NAN, Float::INFINITY, "invalid" ].each do |interval|
      assert_raises(ArgumentError) do
        Operations::DurableEnqueueHeartbeat.new(context:, interval:)
      end
    end
  end

  test "renew lease fails closed when the catalog entry is missing or mismatched" do
    now = Time.current
    intent = create_intent(source_id: 82, dedupe_key: "test:renew-missing-catalog:82")
    attempt = intent.attempts.create!(
      generation: 1,
      attempt_number: 1,
      lease_token: SecureRandom.uuid,
      job_id: SecureRandom.uuid,
      trigger: "maintenance",
      started_at: now,
      lease_expires_at: now + 1.minute
    )
    intent.with_lock do
      state = Operations::DurableEnqueueReducer.call(intent)
      Operations::DurableEnqueueLedger.append_locked!(
        intent:,
        state:,
        event_type: "attempt_started",
        generation: 1,
        attempt:,
        metadata: { attempt_number: 1 },
        occurred_at: now
      )
    end
    attributes = {
      intent_id: intent.id,
      attempt_id: attempt.id,
      generation: 1,
      lease_token: attempt.lease_token,
      now: now + 1.second
    }

    Operations::DurableEnqueueCatalog.stub(:entry, nil) do
      result = Operations::RenewDurableEnqueueLease.call(**attributes)
      assert_predicate result, :failure?
      assert_equal "durable_enqueue_handler_missing", result.code
    end

    mismatch = Struct.new(:source_kind, :queue_name, :lease_seconds).new(
      intent.source_kind,
      "different",
      60
    )
    Operations::DurableEnqueueCatalog.stub(:entry, mismatch) do
      result = Operations::RenewDurableEnqueueLease.call(**attributes)
      assert_predicate result, :failure?
      assert_equal "durable_enqueue_handler_contract_mismatch", result.code
    end

    assert_equal 0, intent.events.where(event_type: "lease_renewed").count
  end

  private

    def insert_native_lease_expired!(intent:, attempt:, occurred_at:)
      connection = Operations::DurableEnqueueEvent.connection
      sequence = intent.events.maximum(:sequence).to_i + 1
      timestamp = connection.quote(occurred_at)
      metadata = connection.quote({ attempt_number: attempt.attempt_number }.to_json)
      connection.execute(<<~SQL)
        INSERT INTO operations_durable_enqueue_events
          (intent_id, attempt_id, sequence, generation, event_type, metadata,
           occurred_at, created_at, updated_at)
        VALUES
          (#{intent.id}, #{attempt.id}, #{sequence}, #{attempt.generation}, 'lease_expired',
           #{metadata}::jsonb, #{timestamp}, #{timestamp}, #{timestamp})
      SQL
    end

    def create_intent(source_id:, dedupe_key:, requested_at: Time.current)
      intent = nil
      collect_after_commit do
        Operations::DurableEnqueueIntent.transaction do
          intent = Operations::DurableEnqueue.record!(
            handler: "community.web_push",
            source_id:,
            dedupe_key:,
            requested_at:
          )
        end
      end
      intent
    end

    def dead_letter_intent!(intent)
      Operations::DurableEnqueueLedger.append!(
        intent:,
        event_type: "dead_lettered",
        generation: 1,
        error_code: "test_delivery_failed",
        occurred_at: Time.current
      )
    end

    def create_intent_for_entry(entry, source_id:, dedupe_key:)
      intent = nil
      Operations::DurableEnqueueCatalog.stub(:entry, ->(_) { entry }) do
        collect_after_commit do
          Operations::DurableEnqueueIntent.transaction do
            intent = Operations::DurableEnqueue.record!(
              handler: entry.key,
              source_id:,
              dedupe_key:
            )
          end
        end
      end
      intent
    end

    def custom_reopen_entry(key:, permission:)
      core_entry = Operations::DurableEnqueueCatalog.entry("community.web_push")
      Operations::DurableEnqueueRegistry::Entry.new(
        **core_entry.to_h.merge(
          key:,
          manual_reopen_permission: permission
        )
      )
    end

    def collect_after_commit(&block)
      ActiveRecord.stub(:after_all_transactions_commit, ->(&callback) { @callbacks << callback }, &block)
    end

    def suppress_after_commit(&block)
      ActiveRecord.stub(:after_all_transactions_commit, ->(&) { }, &block)
    end
  end
end

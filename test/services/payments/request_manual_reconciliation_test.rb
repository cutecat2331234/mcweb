# frozen_string_literal: true

require "test_helper"

module Payments
  class RequestManualReconciliationTest < ActiveSupport::TestCase
    class FailingJob
      def self.perform_later(**)
        raise "queue unavailable"
      end
    end

    setup do
      @now = Time.utc(2026, 7, 26, 12)
      @date = Date.new(2026, 7, 20)
      @actor = create_user
      grant_permission(@actor, RequestManualReconciliation::PERMISSION)
      @config = Payments::ProviderConfig.find_or_initialize_by(
        provider: "stripe"
      )
      @config.assign_attributes(
        enabled: true,
        mode: "test",
        credentials: {
          "secret_key" => "sk_test_manual_reconciliation",
          "webhook_secret" => "whsec_manual_reconciliation"
        }
      )
      @config.save!
      mark_stripe_provider_connection_tested!(
        @config,
        actor: @actor,
        tested_at: @now
      )
      @token = Payments::ManualReconciliationToken.issue(
        actor: @actor,
        config: @config,
        date: @date
      )
    end

    test "reserves one UTC day, records a safe audit, and queues a nonrefreshing job" do
      result = nil

      assert_difference "Payments::ReconciliationRun.count", 1 do
        result = request_reconciliation
      end

      assert result.success?, result.error
      assert result.value[:enqueued]
      assert_equal "enqueued", result.value[:disposition]
      run = result.value[:run].reload
      assert run.pending?
      assert_equal @date, run.window_start.utc.to_date
      assert_equal @date + 1, run.window_end.utc.to_date
      assert_nil run.processing_token
      assert_enqueued_with(
        job: Payments::DailyReconciliationJob,
        args: [
          {
            date: @date.iso8601,
            refresh: false,
            run_id: run.id,
            config_binding: Payments::ReconciliationConfigBinding.generate(
              config: @config.reload,
              run: run
            )
          }
        ]
      )

      audit = AuditLog.find_by!(
        action: RequestManualReconciliation::AUDIT_ACTION,
        resource_type: "Payments::ReconciliationRun",
        resource_id: run.id,
        actor_id: @actor.id
      )
      assert_equal(
        {
          "provider" => "stripe",
          "mode" => "test",
          "reconciliation_date" => @date.iso8601
        },
        audit.metadata
      )
      refute_includes audit.attributes.to_json, "sk_test_manual_reconciliation"
      refute_includes audit.attributes.to_json, "whsec_manual_reconciliation"
    end

    test "duplicate submissions share the reservation and enqueue only once" do
      first = request_reconciliation
      assert first.success?
      assert_equal 1, enqueued_jobs.count
      reissue_token!

      second = nil
      assert_no_enqueued_jobs do
        second = request_reconciliation
      end

      assert second.success?
      refute second.value[:enqueued]
      assert_equal "already_queued", second.value[:disposition]
      assert_equal first.value[:run].id, second.value[:run].id
      assert_equal 1, AuditLog.by_action(
        RequestManualReconciliation::AUDIT_ACTION
      ).where(
        resource_type: "Payments::ReconciliationRun",
        resource_id: first.value[:run].id
      ).count
    end

    test "an active lease wins without queueing another job" do
      window_start = Time.utc(@date.year, @date.month, @date.day)
      run = Payments::ReconciliationRun.create!(
        provider: "stripe",
        mode: "test",
        window_start: window_start,
        window_end: window_start + 1.day,
        status: "running",
        phase: "refunds",
        processing_token: SecureRandom.hex(24),
        last_heartbeat_at: @now,
        attempt_count: 1
      )

      result = nil
      assert_no_enqueued_jobs do
        result = request_reconciliation
      end

      assert result.success?
      refute result.value[:enqueued]
      assert_equal "already_running", result.value[:disposition]
      assert run.reload.running?
      refute AuditLog.by_action(
        RequestManualReconciliation::AUDIT_ACTION
      ).where(
        resource_type: "Payments::ReconciliationRun",
        resource_id: run.id
      ).exists?
    end

    test "a recently completed manual request cannot be submitted twice" do
      first = request_reconciliation
      first.value[:run].update!(
        status: "completed",
        phase: "completed",
        completed_at: @now,
        last_heartbeat_at: @now
      )
      clear_enqueued_jobs
      reissue_token!

      result = nil
      assert_no_enqueued_jobs do
        result = request_reconciliation
      end

      assert result.success?
      refute result.value[:enqueued]
      assert_equal "recently_requested", result.value[:disposition]
      assert first.value[:run].reload.completed?
    end

    test "strict UTC date range, confirmation, token, and permission checks fail closed" do
      bounds = RequestManualReconciliation.date_bounds(at: @now)
      assert_equal Date.new(2025, 7, 26), bounds.begin
      assert_equal Date.new(2026, 7, 25), bounds.end

      [
        [ "2026-7-20", "invalid_date" ],
        [ "not-a-date", "invalid_date" ],
        [ "2025-07-25", "date_out_of_range" ],
        [ "2026-07-26", "date_out_of_range" ]
      ].each do |date, code|
        result = request_reconciliation(
          date: date,
          confirmation: "RECONCILE #{date} UTC"
        )

        assert result.failure?
        assert_equal code, result.code
      end

      mismatch = request_reconciliation(confirmation: "RECONCILE SOMETHING")
      assert mismatch.failure?
      assert_equal "confirmation_mismatch", mismatch.code

      invalid_token = request_reconciliation(token: "invalid")
      assert invalid_token.failure?
      assert_equal "invalid_reconciliation_token", invalid_token.code

      unauthorized_actor = create_user
      forbidden = request_reconciliation(
        actor: unauthorized_actor,
        token: Payments::ManualReconciliationToken.issue(
          actor: unauthorized_actor,
          config: @config,
          date: @date
        )
      )
      assert forbidden.failure?
      assert_equal "forbidden", forbidden.code

      assert_empty enqueued_jobs
      refute AuditLog.by_action(
        RequestManualReconciliation::AUDIT_ACTION
      ).exists?
    end

    test "authorization is actor and configuration bound" do
      other_actor = create_user
      grant_permission(other_actor, RequestManualReconciliation::PERMISSION)

      refute Payments::ManualReconciliationToken.valid?(
        @token,
        actor: other_actor,
        config: @config,
        date: @date
      )

      @config.touch
      refute Payments::ManualReconciliationToken.valid?(
        @token,
        actor: @actor,
        config: @config.reload,
        date: @date
      )
    end

    test "authorization is date bound and its nonce can be consumed only once" do
      refute Payments::ManualReconciliationToken.valid?(
        @token,
        actor: @actor,
        config: @config,
        date: @date - 1.day
      )
      assert Payments::ManualReconciliationToken.consume?(
        @token,
        actor: @actor,
        config: @config,
        date: @date
      )
      refute Payments::ManualReconciliationToken.consume?(
        @token,
        actor: @actor,
        config: @config,
        date: @date
      )
    end

    test "enqueue failure is visible and can be retried despite the cooldown" do
      failed = request_reconciliation(job_class: FailingJob)

      assert failed.failure?
      assert_equal "enqueue_failed", failed.code
      run = Payments::ReconciliationRun.find_by!(
        provider: "stripe",
        mode: "test",
        window_start: Time.utc(2026, 7, 20)
      )
      assert run.failed?
      assert_equal RequestManualReconciliation::ENQUEUE_FAILURE_CODE,
        run.failure_code

      reissue_token!
      retried = nil
      assert_enqueued_with(job: Payments::DailyReconciliationJob) do
        retried = request_reconciliation
      end

      assert retried.success?
      assert retried.value[:enqueued]
      assert run.reload.pending?
      assert_nil run.failure_code
    end

    private

    def reissue_token!
      @token = Payments::ManualReconciliationToken.issue(
        actor: @actor,
        config: @config.reload,
        date: @date
      )
    end

    def request_reconciliation(
      actor: @actor,
      date: @date.iso8601,
      token: @token,
      confirmation: RequestManualReconciliation.confirmation_for(@date),
      job_class: Payments::DailyReconciliationJob
    )
      RequestManualReconciliation.call(
        actor: actor,
        date: date,
        token: token,
        confirmation: confirmation,
        clock: -> { @now },
        job_class: job_class,
        ip_address: "192.0.2.10",
        user_agent: "Manual reconciliation test"
      )
    end
  end
end

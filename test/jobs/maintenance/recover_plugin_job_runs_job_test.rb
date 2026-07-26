# frozen_string_literal: true

require "stringio"
require "test_helper"
require "mcweb/plugins/job_recovery"

module Maintenance
  class RecoverPluginJobRunsJobTest < ActiveJob::TestCase
    test "requeues stale due and lease-expired runs without touching fresh leases" do
      now = Time.zone.parse("2026-07-26 12:00:00")
      due = create_run(
        public_id: SecureRandom.uuid,
        status: "queued",
        scheduled_at: now - 10.minutes,
        enqueued_at: now - 10.minutes
      )
      expired = create_run(
        public_id: SecureRandom.uuid,
        status: "running",
        attempts: 1,
        scheduled_at: now - 20.minutes,
        enqueued_at: now - 10.minutes,
        lease_expires_at: now - 1.minute
      )
      fresh = create_run(
        public_id: SecureRandom.uuid,
        status: "running",
        attempts: 1,
        scheduled_at: now - 1.minute,
        enqueued_at: now - 1.minute,
        lease_expires_at: now + 10.minutes
      )

      travel_to(now) do
        assert_operator Mcweb::Plugins::JobRecovery.call(now:), :>=, 2
      end

      recovered_ids = enqueued_jobs
        .select { |job| job.fetch(:job) == PluginOwnedJob }
        .map { |job| job.fetch(:args).first }
      assert_includes recovered_ids, due.public_id
      assert_includes recovered_ids, expired.public_id
      assert_not_includes recovered_ids, fresh.public_id
      assert_equal now, due.reload.recovery_claimed_at
      assert_equal now, expired.reload.recovery_claimed_at

      clear_enqueued_jobs
      travel_to(now + 1.minute) do
        assert_equal 0, Mcweb::Plugins::JobRecovery.call(now: now + 1.minute)
      end
      assert_empty enqueued_jobs
    end

    test "enqueue failures remain queued and are retried without leaking details" do
      now = Time.zone.parse("2026-07-26 12:00:00")
      run = create_run(
        public_id: SecureRandom.uuid,
        scheduled_at: now - 1.minute
      )
      original_set = PluginOwnedJob.method(:set)
      original_logger = Rails.logger
      log_output = StringIO.new
      secret = "queue-adapter-secret"

      PluginOwnedJob.define_singleton_method(:set) { |**| raise RuntimeError, secret }
      Rails.logger = ActiveSupport::Logger.new(log_output)
      travel_to(now) do
        assert_nil Mcweb::Plugins::JobStore.schedule!(
          public_id: run.public_id,
          scheduled_at: run.scheduled_at
        )
      end

      run.reload
      assert_equal "queued", run.status
      assert_nil run.enqueued_at
      assert_equal "enqueue_failed", run.last_enqueue_error_code
      assert_equal now, run.recovery_claimed_at
      refute_includes log_output.string, secret
      refute_includes log_output.string, run.arguments.fetch("message")
      refute_includes log_output.string, run.idempotency_key

      PluginOwnedJob.define_singleton_method(:set, original_set)
      Rails.logger = original_logger
      travel_to(now + 1.minute) do
        assert_equal 0, Mcweb::Plugins::JobRecovery.call(now: now + 1.minute)
      end
      travel_to(now + 6.minutes) do
        assert_equal 1, Mcweb::Plugins::JobRecovery.call(now: now + 6.minutes)
      end

      run.reload
      assert_equal "queued", run.status
      assert_equal now + 6.minutes, run.enqueued_at
      assert_equal now + 6.minutes, run.recovery_claimed_at
      assert_nil run.last_enqueue_error_code
    ensure
      PluginOwnedJob.define_singleton_method(:set, original_set) if original_set
      Rails.logger = original_logger if original_logger
    end

    test "recovery cron runs every minute on maintenance" do
      schedule = YAML.safe_load_file(Rails.root.join("config/sidekiq_cron.yml"))
      recovery = schedule.fetch("recover_plugin_job_runs")

      assert_equal "* * * * *", recovery.fetch("cron")
      assert_equal "Maintenance::RecoverPluginJobRunsJob", recovery.fetch("class")
      assert_equal "maintenance", recovery.fetch("queue")
      assert_equal true, recovery.fetch("active_job")
    end

    private

    def create_run(**attributes)
      PluginJobRun.create!({
        owner_plugin_id: "acme/jobs",
        plugin_version: "1.0.0",
        job_key: "deliver",
        contribution_schema_version: "1",
        declaration_digest: "a" * 64,
        arguments: { "message" => "encrypted" },
        payload_digest: SecureRandom.hex(32),
        idempotency_key: "recovery:#{SecureRandom.hex(8)}",
        status: "queued",
        attempts: 0,
        max_attempts: 3,
        retry_wait_seconds: 5,
        lease_seconds: 60,
        requested_wait_seconds: 0,
        scheduled_at: Time.current
      }.merge(attributes))
    end
  end
end

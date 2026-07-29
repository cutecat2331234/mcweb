# frozen_string_literal: true

require "test_helper"

module Operations
  module Metrics
    class InstrumentationTest < ActiveSupport::TestCase
      FakeEvent = Data.define(:name, :payload, :duration, :end)

      class Recorder
        attr_reader :calls

        def initialize
          @calls = []
        end

        def record(metric_name, **options)
          @calls << {
            metric_name:,
            options:
          }
          true
        end
      end

      test "collects required lifecycle events without copying sensitive payloads" do
        recorder = Recorder.new
        collector = Instrumentation.new(
          recorder:,
          slow_query_ms: 100
        )
        now = Time.zone.parse("2026-07-29 16:00:00")

        collector.record_request(event(
          "process_action.action_controller",
          now:,
          duration: 125,
          payload: {
            controller: "Admin::UsersController",
            status: 503,
            path: "/admin/users?token=secret",
            user_id: 99,
            email: "private@example.com"
          }
        ))
        collector.record_sql(event(
          "sql.active_record",
          now:,
          duration: 200,
          payload: {
            name: "User Load",
            sql: "SELECT * FROM users WHERE email = 'private@example.com'",
            binds: [ "Bearer secret" ]
          }
        ))
        collector.record_job(event(
          "perform.active_job",
          now:,
          duration: 75,
          payload: {
            job: Struct.new(:queue_name).new("payments"),
            exception: [ "RuntimeError", "private@example.com" ]
          }
        ))
        collector.record_mail(event(
          "deliver.action_mailer",
          now:,
          duration: 25,
          payload: {
            to: [ "private@example.com" ],
            message_id: "secret-message"
          }
        ))
        collector.record_payment_webhook(event(
          "payments.webhook.processed",
          now:,
          payload: {
            provider: "stripe",
            outcome: "processed",
            event_id: "evt_secret",
            error_code: "private"
          }
        ))
        collector.record_community_upload(event(
          "community.upload.stored",
          now:,
          payload: {
            kind: "post_attachment",
            user_id: 99,
            upload_id: 88,
            filename: "private.txt"
          }
        ))
        collector.record_community_scan(event(
          "community.attachment.scan_infected",
          now:,
          payload: {
            user_id: 99,
            upload_id: 88,
            scanner: "secret-scanner"
          }
        ))

        names = recorder.calls.map { |call| call.fetch(:metric_name) }
        assert_includes names, "request.duration_ms"
        assert_includes names, "request.server_error"
        assert_includes names, "database.slow_query.duration_ms"
        assert_includes names, "job.execution.duration_ms"
        assert_includes names, "job.failure"
        assert_includes names, "mail.delivery.duration_ms"
        assert_includes names, "payments.webhook.processed"
        assert_includes names, "community.upload.event"
        assert_includes names, "community.scan.event"

        serialized = recorder.calls.to_json
        refute_includes serialized, "private@example.com"
        refute_includes serialized, "evt_secret"
        refute_includes serialized, "SELECT *"
        refute_includes serialized, "Bearer"
        refute_includes serialized, "user_id"
        refute_includes serialized, "/admin/users"
      end

      test "ignores cached and below-threshold database events" do
        recorder = Recorder.new
        collector = Instrumentation.new(
          recorder:,
          slow_query_ms: 100
        )
        now = Time.zone.parse("2026-07-29 16:00:00")

        collector.record_sql(event(
          "sql.active_record",
          now:,
          duration: 500,
          payload: { name: "User Load", cached: true }
        ))
        collector.record_sql(event(
          "sql.active_record",
          now:,
          duration: 99,
          payload: { name: "User Load" }
        ))
        collector.record_sql(event(
          "sql.active_record",
          now:,
          duration: 500,
          payload: { name: "SCHEMA" }
        ))

        assert_empty recorder.calls
      end

      test "notification subscriptions receive and normalize real events" do
        recorder = Recorder.new
        collector = Instrumentation.new(recorder:)
        collector.install!

        ActiveSupport::Notifications.instrument(
          "payments.webhook.processed",
          provider: "stripe",
          outcome: "processed",
          event_id: "must-not-be-copied"
        )

        call = recorder.calls.fetch(0)
        assert_equal "payments.webhook.processed",
          call.fetch(:metric_name)
        assert_equal(
          { provider: "stripe", outcome: "processed" },
          call.dig(:options, :dimensions)
        )
        assert_respond_to call.dig(:options, :at), :to_time
        refute_includes call.to_json, "must-not-be-copied"
      ensure
        collector&.uninstall!
      end

      test "handled Active Job retries count one failed execution" do
        recorder = Recorder.new
        collector = Instrumentation.new(recorder:)
        now = Time.zone.parse("2026-07-29 16:00:00")
        job = Struct.new(:queue_name).new("maintenance")

        collector.record_job_failure_signal(event(
          "enqueue_retry.active_job",
          now:,
          payload: {
            job:,
            error: RuntimeError.new("sensitive retry reason")
          }
        ))
        collector.record_job(event(
          "perform.active_job",
          now:,
          duration: 120,
          payload: { job: }
        ))

        assert_equal 1, recorder.calls.count { |call|
          call.fetch(:metric_name) == "job.failure"
        }
        execution = recorder.calls.find { |call|
          call.fetch(:metric_name) == "job.execution.duration_ms"
        }
        assert_equal "failure",
          execution.dig(:options, :dimensions, :outcome)
        refute_includes recorder.calls.to_json, "sensitive retry reason"
      end

      private

      def event(name, now:, payload:, duration: 1)
        FakeEvent.new(
          name:,
          payload:,
          duration:,
          end: now
        )
      end
    end
  end
end

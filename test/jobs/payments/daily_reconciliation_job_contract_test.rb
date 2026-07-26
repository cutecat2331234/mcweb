# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

module Payments
  class DailyReconciliationJobContractTest < ActiveJob::TestCase
    class RecordingReconciler
      attr_reader :calls

      def initialize(outcomes = [])
        @outcomes = outcomes.dup
        @calls = []
      end

      def call(**arguments)
        @calls << arguments
        @outcomes.shift || ServiceResult.success(run: nil)
      end
    end

    test "the default run fans out the previous seven UTC dates newest first" do
      reconciler = RecordingReconciler.new

      travel_to Time.utc(2026, 7, 26, 0, 30) do
        assert_enqueued_jobs 7, only: Payments::DailyReconciliationJob do
          with_reconciler(reconciler) do
            Payments::DailyReconciliationJob.new.perform
          end
        end
      end

      %w[
        2026-07-25
        2026-07-24
        2026-07-23
        2026-07-22
        2026-07-21
        2026-07-20
        2026-07-19
      ].each do |date|
        assert_enqueued_with(
          job: Payments::DailyReconciliationJob,
          args: [ { date: date, refresh: true } ]
        )
      end
      assert_empty reconciler.calls
    end

    test "a requested reconciliation date bypasses the rolling lookback" do
      reconciler = RecordingReconciler.new
      requested_date = Date.new(2026, 7, 5)

      with_reconciler(reconciler) do
        Payments::DailyReconciliationJob.new.perform(date: requested_date)
      end

      assert_equal [ { date: requested_date, refresh: true } ], reconciler.calls
    end

    test "a manually reserved date can opt out of a second refresh" do
      reconciler = RecordingReconciler.new

      with_reconciler(reconciler) do
        Payments::DailyReconciliationJob.new.perform(
          date: "2026-07-05",
          refresh: false,
          run_id: 42,
          config_binding: "a" * 64
        )
      end

      assert_equal(
        [
          {
            date: "2026-07-05",
            refresh: false,
            reserved_run_id: 42,
            expected_config_binding: "a" * 64
          }
        ],
        reconciler.calls
      )
    end

    test "retryable provider and infrastructure failures raise the retry signal" do
      Payments::DailyReconciliationJob::RETRYABLE_CODES.each do |code|
        reconciler = RecordingReconciler.new(
          [ ServiceResult.failure(error: "Safe failure.", code: code) ]
        )

        error = assert_raises(Payments::ReconciliationRetryableError) do
          with_reconciler(reconciler) do
            Payments::DailyReconciliationJob.new.perform(date: "2026-07-20")
          end
        end

        assert_equal code, error.message
        assert_equal 1, reconciler.calls.length
      end
    end

    test "retry_on schedules another job for a retryable failure" do
      reconciler = RecordingReconciler.new(
        [
          ServiceResult.failure(
            error: "Stripe is temporarily unavailable.",
            code: "provider_unavailable"
          )
        ]
      )

      assert_enqueued_with(job: Payments::DailyReconciliationJob) do
        with_reconciler(reconciler) do
          Payments::DailyReconciliationJob.perform_now(date: "2026-07-20")
        end
      end

      assert_equal 1, reconciler.calls.length
    end

    test "nonretryable failures stop the current pass without scheduling retries" do
      nonretryable_codes = %w[
        authentication_failed
        permission_denied
        invalid_provider_response
        environment_mismatch
        reconciliation_lease_lost
      ]

      nonretryable_codes.each do |code|
        clear_enqueued_jobs
        reconciler = RecordingReconciler.new(
          [ ServiceResult.failure(error: "Safe permanent failure.", code: code) ]
        )

        with_reconciler(reconciler) do
          Payments::DailyReconciliationJob.perform_now(date: "2026-07-20")
        end

        assert_empty enqueued_jobs, "unexpected retry for #{code}"
        assert_equal 1, reconciler.calls.length
      end
    end

    private

    def with_reconciler(reconciler)
      Payments::ReconcileDay.stub(
        :call,
        ->(**arguments) { reconciler.call(**arguments) }
      ) do
        yield
      end
    end
  end
end

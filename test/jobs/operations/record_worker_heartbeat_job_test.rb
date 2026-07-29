# frozen_string_literal: true

require "test_helper"

module Operations
  class RecordWorkerHeartbeatJobTest < ActiveJob::TestCase
    test "records a privacy-safe heartbeat and reuses the process record" do
      first_seen = Time.zone.parse("2026-07-29 14:00:00")
      second_seen = first_seen + 1.minute

      assert_difference -> { WorkerHeartbeat.count }, 1 do
        RecordWorkerHeartbeatJob.perform_now(now: first_seen)
      end
      assert_no_difference -> { WorkerHeartbeat.count } do
        RecordWorkerHeartbeatJob.perform_now(now: second_seen)
      end

      heartbeat = WorkerHeartbeat.find_by!(
        process_ref: RecordWorkerHeartbeatJob::PROCESS_REF
      )
      assert_equal first_seen, heartbeat.started_at
      assert_equal second_seen, heartbeat.last_seen_at
      assert_equal "sidekiq", heartbeat.process_kind
      assert_match(/\A[0-9a-f]{64}\z/, heartbeat.process_ref)
      refute_includes heartbeat.attributes.to_json, Process.pid.to_s
    end

    test "removes only expired process records" do
      now = Time.zone.parse("2026-07-29 14:00:00")
      old = WorkerHeartbeat.create!(
        process_ref: "a" * 64,
        process_kind: "sidekiq",
        started_at: now - 8.days,
        last_seen_at: now - WorkerHeartbeat::RETAIN_FOR - 1.second
      )
      recent = WorkerHeartbeat.create!(
        process_ref: "b" * 64,
        process_kind: "sidekiq",
        started_at: now - 1.day,
        last_seen_at: now - 1.day
      )

      RecordWorkerHeartbeatJob.perform_now(now:)

      assert_not WorkerHeartbeat.exists?(old.id)
      assert WorkerHeartbeat.exists?(recent.id)
    end
  end
end

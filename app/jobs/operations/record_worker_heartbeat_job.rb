# frozen_string_literal: true

require "digest"
require "securerandom"

module Operations
  class RecordWorkerHeartbeatJob < ApplicationJob
    queue_as :maintenance

    PROCESS_REF = Digest::SHA256.hexdigest(
      "#{Process.pid}:#{SecureRandom.uuid}"
    ).freeze

    def perform(now: Time.current)
      timestamp = now.to_time.utc
      heartbeat = WorkerHeartbeat.find_or_initialize_by(
        process_ref: PROCESS_REF
      )
      heartbeat.assign_attributes(
        process_kind: "sidekiq",
        started_at: heartbeat.started_at || timestamp,
        last_seen_at: timestamp
      )
      heartbeat.save!

      WorkerHeartbeat
        .where("last_seen_at < ?", timestamp - WorkerHeartbeat::RETAIN_FOR)
        .delete_all
      heartbeat
    end
  end
end

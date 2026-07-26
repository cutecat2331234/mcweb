# frozen_string_literal: true

require_relative "job_store"

module Mcweb
  module Plugins
    class JobRecovery
      BATCH_SIZE = 100
      REENQUEUE_INTERVAL = 5.minutes

      def self.call(now: Time.current)
        new(now:).call
      end

      def initialize(now:)
        @now = now
      end

      def call
        public_ids = reserve_recoverable_runs
        public_ids.count do |public_id|
          record = PluginJobRun.select(:public_id, :scheduled_at).find_by(public_id:)
          next unless record

          JobStore.schedule!(
            public_id: record.public_id,
            scheduled_at: [ record.scheduled_at, @now ].max
          ).present?
        end
      end

      private

      def reserve_recoverable_runs
        stale_before = @now - REENQUEUE_INTERVAL
        records = []
        PluginJobRun.transaction do
          records = recoverable_scope(stale_before)
            .order(:scheduled_at, :id)
            .limit(BATCH_SIZE)
            .lock("FOR UPDATE SKIP LOCKED")
            .to_a
          ids = records.map(&:id)
          PluginJobRun.where(id: ids).update_all(
            recovery_claimed_at: @now,
            updated_at: @now
          ) if ids.any?
        end
        records.map(&:public_id).freeze
      end

      def recoverable_scope(stale_before)
        due_base = PluginJobRun
          .where(status: %w[queued retrying])
          .where(scheduled_at: ..@now)
        due = due_base
          .where(enqueued_at: nil)
          .or(
            due_base.where(enqueued_at: ..stale_before)
          )
          .or(
            due_base.where(last_enqueue_error_code: "enqueue_failed")
          )
        expired = PluginJobRun.where(status: "running", lease_expires_at: ..@now)
        recoverable = due.or(expired)
        recoverable
          .where(recovery_claimed_at: nil)
          .or(
            recoverable.where(recovery_claimed_at: ..stale_before)
          )
      end
    end
  end
end

# frozen_string_literal: true

require_relative "job_store"
require_relative "registry"
require_relative "../plugin_api/v1/job_context"

module Mcweb
  module Plugins
    class JobRunner
      Claim = Data.define(:record, :attempt)

      def perform(public_id)
        record = PluginJobRun.find_by(public_id: public_id.to_s)
        return unless record

        claim = claim(record)
        return unless claim.is_a?(Claim)

        context = Mcweb::PluginApi::V1::JobContext.new(
          run_public_id: claim.record.public_id,
          owner_plugin_id: claim.record.owner_plugin_id,
          job_key: claim.record.job_key,
          attempt: claim.attempt,
          max_attempts: claim.record.max_attempts,
          scheduled_at: claim.record.scheduled_at
        )
        Mcweb::Plugins.dispatch_job(
          plugin_id: claim.record.owner_plugin_id,
          plugin_version: claim.record.plugin_version,
          contribution_schema_version: claim.record.contribution_schema_version,
          declaration_digest: claim.record.declaration_digest,
          job_key: claim.record.job_key,
          arguments: claim.record.arguments,
          context:
        )
        mark_succeeded(claim)
      rescue JobDispatchError => e
        handle_dispatch_failure(claim, e) if claim.is_a?(Claim)
      rescue Lockbox::DecryptionError
        mark_failed(claim, "job_payload_unreadable") if claim.is_a?(Claim)
      end

      private

      def claim(record)
        now = Time.current
        result = nil
        record.with_lock do
          case record.status
          when "queued", "retrying"
            if record.scheduled_at > now
              result = :skip
              next
            end
          when "running"
            if record.lease_expires_at&.future?
              result = :skip
              next
            end
          else
            result = :skip
            next
          end

          if record.attempts >= record.max_attempts
            record.update!(
              status: "failed",
              finished_at: now,
              lease_expires_at: nil,
              last_error_code: "attempts_exhausted"
            )
            result = :skip
            next
          end

          next_attempt = record.attempts + 1
          record.update!(
            status: "running",
            attempts: next_attempt,
            started_at: now,
            finished_at: nil,
            lease_expires_at: now + record.lease_seconds.seconds,
            recovery_claimed_at: nil,
            last_error_code: nil,
            last_enqueue_error_code: nil
          )
          result = Claim.new(record: record.dup, attempt: next_attempt)
        end

        result
      end

      def mark_succeeded(claim)
        PluginJobRun
          .where(
            public_id: claim.record.public_id,
            status: "running",
            attempts: claim.attempt
          )
          .update_all(
            status: "succeeded",
            finished_at: Time.current,
            lease_expires_at: nil,
            last_error_code: nil,
            updated_at: Time.current
          )
      end

      def handle_dispatch_failure(claim, error)
        if error.code.in?(%w[plugin_unavailable incompatible_job handler_unavailable])
          mark_paused(claim, error.code)
        elsif error.code == "job_payload_invalid"
          mark_failed(claim, error.code)
        else
          retry_or_fail(claim, error.code)
        end
      end

      def mark_paused(claim, code)
        restored_attempts = [ claim.attempt - 1, 0 ].max
        PluginJobRun
          .where(
            public_id: claim.record.public_id,
            status: "running",
            attempts: claim.attempt
          )
          .update_all(
            status: "paused",
            attempts: restored_attempts,
            started_at: restored_attempts.zero? ? nil : claim.record.started_at,
            lease_expires_at: nil,
            last_error_code: code,
            updated_at: Time.current
          )
      end

      def retry_or_fail(claim, code)
        record = PluginJobRun.find_by(
          public_id: claim.record.public_id,
          status: "running",
          attempts: claim.attempt
        )
        return unless record

        if claim.attempt < record.max_attempts
          retry_at = Time.current + record.retry_wait_seconds.seconds
          updated = PluginJobRun
            .where(id: record.id, status: "running", attempts: claim.attempt)
            .update_all(
              status: "retrying",
              scheduled_at: retry_at,
              lease_expires_at: nil,
              last_error_code: code,
              updated_at: Time.current
            )
          JobStore.schedule!(public_id: record.public_id, scheduled_at: retry_at) if updated == 1
        else
          mark_failed(claim, "attempts_exhausted")
        end
      end

      def mark_failed(claim, code)
        PluginJobRun
          .where(
            public_id: claim.record.public_id,
            status: "running",
            attempts: claim.attempt
          )
          .update_all(
            status: "failed",
            finished_at: Time.current,
            lease_expires_at: nil,
            last_error_code: code,
            updated_at: Time.current
          )
      end
    end
  end
end

# frozen_string_literal: true

module Commerce
  class BuildFinanceExportJob < ApplicationJob
    queue_as :default

    def perform(finance_export_id)
      finance_export = FinanceExport.find_by(id: finance_export_id)
      return unless finance_export
      return unless claim!(finance_export)

      unless permitted?(finance_export.requested_by)
        return fail_export!(finance_export, "finance_export_permission_revoked")
      end

      generated = FinanceCsvExport.call(filters: finance_export.filters)
      return fail_export!(finance_export, generated.code || "finance_export_generation_failed") if generated.failure?

      value = generated.value
      finance_export.file.attach(
        io: value.fetch(:io),
        filename: "mcweb-finance-#{finance_export.public_id}.csv",
        content_type: "text/csv"
      )

      complete!(finance_export, value)
    rescue StandardError => e
      Rails.logger.error("finance export job failed: #{e.class}")
      fail_export!(finance_export, "finance_export_generation_failed") if finance_export&.persisted?
    end

    private

    def claim!(finance_export)
      claimed = false
      FinanceExport.transaction do
        finance_export.lock!
        return false unless finance_export.queued?

        before = { status: finance_export.status, progress_percent: finance_export.progress_percent }
        finance_export.update!(
          status: "running",
          progress_percent: 10,
          started_at: Time.current,
          attempts: finance_export.attempts + 1,
          error_code: nil
        )
        record_transition!(
          finance_export,
          actor: finance_export.requested_by,
          status: "running",
          before:,
          after: { status: "running", progress_percent: 10 }
        )
        claimed = true
      end
      claimed
    end

    def complete!(finance_export, value)
      FinanceExport.transaction do
        finance_export.lock!
        if finance_export.revoked?
          finance_export.file.purge_later if finance_export.file.attached?
          return
        end
        return unless finance_export.running?

        before = { status: finance_export.status, progress_percent: finance_export.progress_percent }
        now = Time.current
        finance_export.update!(
          status: "completed",
          progress_percent: 100,
          row_count: value.fetch(:row_count),
          file_sha256: value.fetch(:file_sha256),
          completed_at: now,
          expires_at: FinanceRetentionPolicy.export_file_expires_at(from: now),
          failed_at: nil,
          error_code: nil
        )
        record_transition!(
          finance_export,
          actor: finance_export.requested_by,
          status: "completed",
          before:,
          after: {
            status: "completed",
            progress_percent: 100,
            row_count: finance_export.row_count,
            expires_at: finance_export.expires_at.iso8601
          }
        )
      end
    rescue StandardError
      finance_export.file.purge_later if finance_export.file.attached? && !finance_export.completed?
      raise
    end

    def fail_export!(finance_export, error_code)
      finance_export.file.purge_later if finance_export.file.attached?
      FinanceExport.transaction do
        finance_export.lock!
        return if finance_export.revoked? || finance_export.completed? || finance_export.expired?

        before = { status: finance_export.status, progress_percent: finance_export.progress_percent }
        finance_export.update!(
          status: "failed",
          failed_at: Time.current,
          error_code: error_code.to_s.first(100)
        )
        record_transition!(
          finance_export,
          actor: finance_export.requested_by,
          status: "failed",
          before:,
          after: {
            status: "failed",
            progress_percent: finance_export.progress_percent,
            error_code: finance_export.error_code
          }
        )
      end
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def record_transition!(finance_export, actor:, status:, before:, after:)
      finance_export.events.create!(
        actor:,
        status:,
        progress_percent: finance_export.progress_percent,
        metadata: after,
        created_at: Time.current
      )
      Administration::AuditLogger.call(
        actor:,
        action: "commerce.finance_export_#{status}",
        resource: finance_export,
        request_id: finance_export.idempotency_key,
        before_state: before,
        after_state: after,
        metadata: {
          export_public_id: finance_export.public_id,
          filters_digest: finance_export.filters_digest
        }
      )
    end

    def permitted?(actor)
      actor.permission?("store.finance.read") &&
        actor.permission?("store.finance.exports.create")
    end
  end
end

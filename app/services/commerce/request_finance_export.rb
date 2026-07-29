# frozen_string_literal: true

require "digest"

module Commerce
  class RequestFinanceExport < ApplicationService
    CREATE_PERMISSION = "store.finance.exports.create"
    READ_PERMISSION = "store.finance.read"
    ACTIVE_LIMIT = 5
    UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

    def initialize(actor:, filters:, idempotency_key:, ip_address: nil, user_agent: nil)
      @actor = actor
      @filters = FinanceDocumentQuery.normalize(filters)
      @idempotency_key = idempotency_key.to_s.strip.downcase
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      return failure("finance_export_unauthorized") unless authorized?
      return failure("finance_export_idempotency_key_invalid") unless @idempotency_key.match?(UUID_FORMAT)

      digest = filters_digest
      existing = FinanceExport.find_by(requested_by: @actor, idempotency_key: @idempotency_key)
      return replay_result(existing, digest) if existing

      if FinanceExport.where(requested_by: @actor, status: %w[queued running]).count >= ACTIVE_LIMIT
        return failure("finance_export_active_limit")
      end

      finance_export = nil
      FinanceExport.transaction do
        finance_export = FinanceExport.create!(
          requested_by: @actor,
          status: "queued",
          format: "csv",
          idempotency_key: @idempotency_key,
          filters_digest: digest,
          filters: @filters,
          progress_percent: 0,
          requested_at: Time.current,
          retention_until: FinanceRetentionPolicy.export_metadata_retention_until
        )
        finance_export.events.create!(
          actor: @actor,
          status: "queued",
          progress_percent: 0,
          request_id: @idempotency_key,
          metadata: { filters_digest: digest },
          created_at: Time.current
        )
        Administration::AuditLogger.call(
          actor: @actor,
          action: "commerce.finance_export_requested",
          resource: finance_export,
          request_id: @idempotency_key,
          after_state: {
            status: finance_export.status,
            filters: finance_export.filters
          },
          metadata: {
            export_public_id: finance_export.public_id,
            filters_digest: digest
          },
          ip_address: @ip_address,
          user_agent: @user_agent
        )
      end

      ActiveRecord.after_all_transactions_commit do
        Commerce::BuildFinanceExportJob.perform_later(finance_export.id)
      end
      ServiceResult.success(finance_export:, replayed: false)
    rescue ActiveRecord::RecordNotUnique
      replay_result(
        FinanceExport.find_by!(requested_by: @actor, idempotency_key: @idempotency_key),
        digest
      )
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash, code: "finance_export_invalid")
    end

    private

    def authorized?
      @actor&.permission?(READ_PERMISSION) && @actor.permission?(CREATE_PERMISSION)
    end

    def filters_digest
      Digest::SHA256.hexdigest(JSON.generate(@filters.sort.to_h))
    end

    def replay_result(existing, expected_digest)
      return failure("finance_export_idempotency_conflict") unless existing.filters_digest == expected_digest

      ServiceResult.success(finance_export: existing, replayed: true)
    end

    def failure(code)
      ServiceResult.failure(error: code, code:)
    end
  end
end

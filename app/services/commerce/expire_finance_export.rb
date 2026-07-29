# frozen_string_literal: true

module Commerce
  class ExpireFinanceExport < ApplicationService
    def initialize(finance_export:, now: Time.current)
      @finance_export = finance_export
      @now = now
    end

    def call
      attachment = nil
      expired = false

      FinanceExport.transaction do
        finance_export = FinanceExport.lock.find(@finance_export.id)
        return ServiceResult.success(finance_export:, expired: false) unless expirable?(finance_export)

        before = { status: finance_export.status, expires_at: finance_export.expires_at&.iso8601 }
        attachment = finance_export.file if finance_export.file.attached?
        finance_export.update!(status: "expired")
        finance_export.events.create!(
          status: "expired",
          progress_percent: finance_export.progress_percent,
          metadata: { expired_at: @now.iso8601 },
          created_at: @now
        )
        Administration::AuditLogger.call(
          action: "commerce.finance_export_expired",
          resource: finance_export,
          before_state: before,
          after_state: { status: "expired", expires_at: finance_export.expires_at&.iso8601 },
          metadata: { export_public_id: finance_export.public_id }
        )
        expired = true
      end

      attachment&.purge_later
      ServiceResult.success(finance_export: @finance_export.reload, expired:)
    rescue ActiveRecord::RecordNotFound
      ServiceResult.failure(error: "finance_export_not_found", code: "finance_export_not_found")
    end

    private

    def expirable?(finance_export)
      finance_export.completed? &&
        finance_export.expires_at.present? &&
        finance_export.expires_at <= @now
    end
  end
end

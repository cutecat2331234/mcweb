# frozen_string_literal: true

module Commerce
  class AuthorizeFinanceExportDownload < ApplicationService
    READ_PERMISSION = "store.finance.read"
    DOWNLOAD_PERMISSION = "store.finance.exports.download"

    def initialize(finance_export:, actor:, ip_address: nil, user_agent: nil, now: Time.current)
      @finance_export = finance_export
      @actor = actor
      @ip_address = ip_address
      @user_agent = user_agent
      @now = now
    end

    def call
      return failure("finance_export_unauthorized") unless authorized?

      expiration = ExpireFinanceExport.call(finance_export: @finance_export, now: @now)
      return expiration if expiration.failure?

      finance_export = nil
      FinanceExport.transaction do
        finance_export = FinanceExport.lock.find(@finance_export.id)
        return failure("finance_export_unavailable") unless finance_export.downloadable?

        finance_export.events.create!(
          actor: @actor,
          status: finance_export.status,
          progress_percent: finance_export.progress_percent,
          metadata: { downloaded_at: @now.iso8601 },
          created_at: @now
        )
        Administration::AuditLogger.call(
          actor: @actor,
          action: "commerce.finance_export_downloaded",
          resource: finance_export,
          metadata: {
            export_public_id: finance_export.public_id,
            file_sha256: finance_export.file_sha256,
            row_count: finance_export.row_count
          },
          ip_address: @ip_address,
          user_agent: @user_agent
        )
      end

      ServiceResult.success(finance_export:)
    end

    private

    def authorized?
      @actor&.permission?(READ_PERMISSION) &&
        @actor.permission?(DOWNLOAD_PERMISSION) &&
        @finance_export.requested_by_id == @actor.id
    end

    def failure(code)
      ServiceResult.failure(error: code, code:)
    end
  end
end

# frozen_string_literal: true

module Commerce
  class RevokeFinanceExport < ApplicationService
    PERMISSION = "store.finance.exports.create"

    def initialize(finance_export:, actor:, ip_address: nil, user_agent: nil)
      @finance_export = finance_export
      @actor = actor
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      return failure("finance_export_unauthorized") unless @actor&.permission?(PERMISSION)

      attachment = nil
      replayed = false
      FinanceExport.transaction do
        finance_export = FinanceExport.lock.find(@finance_export.id)
        unless finance_export.requested_by_id == @actor.id
          return failure("finance_export_unauthorized")
        end

        if finance_export.revoked?
          replayed = true
          next
        end

        before = { status: finance_export.status }
        attachment = finance_export.file if finance_export.file.attached?
        finance_export.update!(
          status: "revoked",
          revoked_at: Time.current,
          expires_at: nil
        )
        finance_export.events.create!(
          actor: @actor,
          status: "revoked",
          progress_percent: finance_export.progress_percent,
          metadata: {},
          created_at: Time.current
        )
        Administration::AuditLogger.call(
          actor: @actor,
          action: "commerce.finance_export_revoked",
          resource: finance_export,
          before_state: before,
          after_state: { status: "revoked" },
          metadata: { export_public_id: finance_export.public_id },
          ip_address: @ip_address,
          user_agent: @user_agent
        )
      end

      attachment&.purge_later
      ServiceResult.success(finance_export: @finance_export.reload, replayed:)
    end

    private

    def failure(code)
      ServiceResult.failure(error: code, code:)
    end
  end
end

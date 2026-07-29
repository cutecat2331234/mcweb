# frozen_string_literal: true

module Identity
  class RetryDataExport < ApplicationService
    def initialize(data_export:, user:, ip_address: nil, user_agent: nil)
      @data_export = data_export
      @user = user
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      retried = false
      DataExport.transaction do
        @data_export.lock!
        return ServiceResult.success(data_export: @data_export, replayed: true) if @data_export.queued? || @data_export.running?
        return failure("data_export_retry_not_allowed") unless @data_export.failed? || @data_export.expired?

        @data_export.archive.purge if @data_export.archive.attached?
        @data_export.update!(
          status: :queued,
          error_code: nil,
          started_at: nil,
          completed_at: nil,
          failed_at: nil,
          revoked_at: nil,
          expires_at: nil,
          requested_at: Time.current
        )
        Administration::AuditLogger.call(
          actor: @user,
          action: "identity.data_export_retried",
          resource: @data_export,
          metadata: { export_public_id: @data_export.public_id },
          ip_address: @ip_address,
          user_agent: @user_agent
        )
        retried = true
      end

      Identity::BuildDataExportJob.perform_later(@data_export.id) if retried
      ServiceResult.success(data_export: @data_export, replayed: !retried)
    rescue ActiveRecord::StaleObjectError
      failure("data_export_conflict")
    end

    private

    def failure(code)
      ServiceResult.failure(error: code, code:)
    end
  end
end

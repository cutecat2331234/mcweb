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
      blob_to_purge = nil
      retried = false
      DataExport.transaction(requires_new: true) do
        @data_export.lock!
        retryable_state = Identity::DataExportGeneration.retryable_state(@data_export)
        if retryable_state.blank?
          if @data_export.queued? || @data_export.running?
            return ServiceResult.success(data_export: @data_export, replayed: true)
          end

          return failure("data_export_retry_not_allowed")
        end

        if @data_export.archive.attached?
          blob_to_purge = @data_export.archive.blob
          @data_export.archive.detach
        end
        @data_export.update!(
          status: :queued,
          error_code: nil,
          started_at: nil,
          completed_at: nil,
          failed_at: nil,
          revoked_at: nil,
          expires_at: nil,
          manifest: {},
          requested_at: next_request_time
        )
        Administration::AuditLogger.call(
          actor: @user,
          action: "identity.data_export_retried",
          resource: @data_export,
          metadata: {
            export_public_id: @data_export.public_id,
            recovery_state: retryable_state
          },
          ip_address: @ip_address,
          user_agent: @user_agent
        )
        Identity::DataExportGeneration.record!(data_export: @data_export)
        retried = true
      end

      Identity::DataExportBlobCleanup.purge_later(blob_to_purge) if retried

      ServiceResult.success(data_export: @data_export, replayed: !retried)
    rescue Operations::DurableEnqueueAdmission::Unavailable
      failure(Operations::DurableEnqueueAdmission::ERROR_CODE)
    rescue ActiveRecord::StaleObjectError
      failure("data_export_conflict")
    end

    private

    def next_request_time
      now = Time.current
      previous = @data_export.requested_at
      previous.present? && previous >= now ? previous + 1.microsecond : now
    end

    def failure(code)
      ServiceResult.failure(error: code, code:)
    end
  end
end

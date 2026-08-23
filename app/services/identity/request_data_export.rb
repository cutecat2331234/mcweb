# frozen_string_literal: true

module Identity
  class RequestDataExport < ApplicationService
    DAILY_LIMIT = 3

    def initialize(user:, idempotency_key:, ip_address: nil, user_agent: nil)
      @user = user
      @idempotency_key = idempotency_key.to_s.strip
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      return failure("idempotency_key_required") if @idempotency_key.blank?
      return failure("idempotency_key_invalid") if @idempotency_key.length > 128

      existing = DataExport.find_by(user: @user, idempotency_key: @idempotency_key)
      return ServiceResult.success(data_export: existing, replayed: true) if existing

      if DataExport.where(user: @user, requested_at: 24.hours.ago..).count >= DAILY_LIMIT
        return failure("data_export_rate_limited")
      end

      data_export = nil
      DataExport.transaction(requires_new: true) do
        data_export = DataExport.create!(
          user: @user,
          idempotency_key: @idempotency_key,
          status: :queued,
          requested_at: Time.current
        )
        Administration::AuditLogger.call(
          actor: @user,
          action: "identity.data_export_requested",
          resource: data_export,
          metadata: { export_public_id: data_export.public_id },
          ip_address: @ip_address,
          user_agent: @user_agent
        )
        Identity::DataExportGeneration.record!(data_export:)
      end

      ServiceResult.success(data_export:, replayed: false)
    rescue Operations::DurableEnqueueAdmission::Unavailable
      failure(Operations::DurableEnqueueAdmission::ERROR_CODE)
    rescue ActiveRecord::RecordNotUnique
      existing = DataExport.find_by!(user: @user, idempotency_key: @idempotency_key)
      ServiceResult.success(data_export: existing, replayed: true)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def failure(code)
      ServiceResult.failure(error: code, code:)
    end
  end
end

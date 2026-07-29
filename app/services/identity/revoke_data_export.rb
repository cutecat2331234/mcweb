# frozen_string_literal: true

module Identity
  class RevokeDataExport < ApplicationService
    def initialize(data_export:, user:, ip_address: nil, user_agent: nil)
      @data_export = data_export
      @user = user
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      attachment = nil
      DataExport.transaction do
        @data_export.lock!
        return ServiceResult.success(data_export: @data_export, replayed: true) if @data_export.revoked?

        attachment = @data_export.archive if @data_export.archive.attached?
        @data_export.update!(
          status: :revoked,
          revoked_at: Time.current,
          expires_at: nil
        )
        Administration::AuditLogger.call(
          actor: @user,
          action: "identity.data_export_revoked",
          resource: @data_export,
          metadata: { export_public_id: @data_export.public_id },
          ip_address: @ip_address,
          user_agent: @user_agent
        )
      end

      attachment&.purge_later
      ServiceResult.success(data_export: @data_export, replayed: false)
    end
  end
end

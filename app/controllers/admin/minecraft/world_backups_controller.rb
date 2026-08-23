# frozen_string_literal: true

module Admin
  module Minecraft
    class WorldBackupsController < BaseController
      include ServiceResponder

      before_action -> { require_permission("minecraft.world_backups.manage") }
      before_action :set_server
      before_action :prevent_response_storage

      def create
        result = ::Minecraft::CreateWorldBackup.call(
          server: @server,
          actor: current_user,
          purpose: "manual",
          request_id: params[:request_id]
        )
        return render_service_error(result) if result.failure?

        value = result.value
        render json: {
          backup: serialize_backup(value.fetch(:backup)),
          idempotent: value.fetch(:idempotent),
          message: t("mcweb.admin.minecraft.world_backup_queued")
        }, status: value.fetch(:idempotent) ? :ok : :accepted
      end

      private

      def set_server
        @server = ::Minecraft::Server.find_by!(public_id: params[:server_id])
      end

      def serialize_backup(backup)
        {
          id: backup.public_id,
          purpose: backup.purpose,
          status: backup.status,
          created_at: backup.created_at&.utc&.iso8601(6),
          verified_at: backup.verified_at&.utc&.iso8601(6),
          archive_bytes: backup.archive_bytes,
          uncompressed_bytes: backup.uncompressed_bytes,
          entry_count: backup.entry_count,
          manifest_digest_short: backup.manifest_digest&.last(12),
          error_code: backup.error_code
        }.compact
      end

      def render_service_error(result)
        render json: {
          error: service_error_message(result),
          code: result.code
        }.compact, status: error_status(result.code)
      end

      def error_status(code)
        return :forbidden if code.to_s.end_with?("unauthorized")
        return :conflict if code.to_s.include?("idempotency_conflict")

        :unprocessable_entity
      end

      def prevent_response_storage
        response.set_header("Cache-Control", "no-store")
      end
    end
  end
end

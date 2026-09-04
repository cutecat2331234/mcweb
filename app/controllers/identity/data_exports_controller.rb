# frozen_string_literal: true

module Identity
  class DataExportsController < ApplicationController
    include PrivateNoStoreResponse
    include ActiveStorage::SetCurrent

    PAGE_SIZE = 25
    DOWNLOAD_URL_TTL = 5.minutes

    before_action :require_login
    before_action :set_data_export, only: %i[download retry revoke]

    def index
      current_user_exports.completed
        .where("expires_at <= ?", Time.current)
        .find_each(&:mark_expired_if_needed!)
      exports, pagination = paginated_exports
      render inertia: "Identity/DataExports/Index", props: {
        exports: exports.map { |data_export| export_payload(data_export) },
        pagination:,
        retention_hours: Identity::BuildDataExportJob::RETENTION.in_hours.to_i,
        daily_limit: Identity::RequestDataExport::DAILY_LIMIT
      }
    end

    def create
      result = Identity::RequestDataExport.call(
        user: current_user,
        idempotency_key: request_params[:idempotency_key],
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      if result.success?
        redirect_to identity_data_exports_path, notice: t("mcweb.flash.data_export_requested")
      else
        redirect_to identity_data_exports_path, alert: service_error_message(result)
      end
    end

    def retry
      result = Identity::RetryDataExport.call(
        data_export: @data_export,
        user: current_user,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      if result.success?
        redirect_to identity_data_exports_path, notice: t("mcweb.flash.data_export_retried")
      else
        redirect_to identity_data_exports_path, alert: service_error_message(result)
      end
    end

    def revoke
      result = Identity::RevokeDataExport.call(
        data_export: @data_export,
        user: current_user,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      if result.success?
        redirect_to identity_data_exports_path, notice: t("mcweb.flash.data_export_revoked")
      else
        redirect_to identity_data_exports_path, alert: service_error_message(result)
      end
    end

    def download
      @data_export.mark_expired_if_needed!
      unless @data_export.reload.downloadable?
        return redirect_to identity_data_exports_path, alert: t("mcweb.flash.data_export_unavailable")
      end

      download_url = @data_export.archive.blob.url(
        expires_in: DOWNLOAD_URL_TTL,
        disposition: :attachment,
        filename: @data_export.archive.filename
      )
      Administration::AuditLogger.call(
        actor: current_user,
        action: "identity.data_export_downloaded",
        resource: @data_export,
        metadata: { export_public_id: @data_export.public_id },
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
      redirect_to download_url, allow_other_host: true
    end

    private

    def current_user_exports
      Identity::DataExport.where(user: current_user)
    end

    def set_data_export
      @data_export = current_user_exports.find_by!(public_id: params[:id])
    end

    def request_params
      params.expect(data_export: [ :idempotency_key ])
    end

    def paginated_exports
      scope = current_user_exports.recent_first
      if params[:cursor].present?
        cursor = current_user_exports.find_by!(public_id: params[:cursor])
        scope = scope.where(
          "requested_at < :requested_at OR (requested_at = :requested_at AND id < :id)",
          requested_at: cursor.requested_at,
          id: cursor.id
        )
      end

      rows = scope.limit(PAGE_SIZE + 1).to_a
      has_more = rows.length > PAGE_SIZE
      rows = rows.first(PAGE_SIZE)
      [
        rows,
        {
          has_more:,
          next_cursor: has_more ? rows.last.public_id : nil,
          page_size: PAGE_SIZE
        }
      ]
    end

    def export_payload(data_export)
      recovery_state = Identity::DataExportGeneration.retryable_state(data_export)
      {
        id: data_export.public_id,
        status: data_export.status,
        requested_at: data_export.requested_at&.iso8601,
        started_at: data_export.started_at&.iso8601,
        completed_at: data_export.completed_at&.iso8601,
        expires_at: data_export.expires_at&.iso8601,
        attempts: data_export.attempts,
        error_code: data_export.error_code,
        retryable: recovery_state.present?,
        recovery_state:,
        downloadable: data_export.downloadable?,
        manifest: data_export.manifest,
        paths: {
          download: download_identity_data_export_path(data_export),
          retry: retry_identity_data_export_path(data_export),
          revoke: revoke_identity_data_export_path(data_export)
        }
      }
    end
  end
end

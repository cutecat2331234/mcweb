# frozen_string_literal: true

module Identity
  class BuildDataExportJob < ApplicationJob
    queue_as :default

    RETENTION = 72.hours

    def perform(data_export_id)
      data_export = DataExport.find_by(id: data_export_id)
      return unless data_export

      started = false
      data_export.with_lock do
        return unless data_export.queued?

        data_export.update!(
          status: :running,
          started_at: Time.current,
          attempts: data_export.attempts + 1
        )
        started = true
      end
      return unless started

      result = DataExportArchive.call(user: data_export.user)
      raise ExportFailed, result.code unless result.success?

      data_export.with_lock do
        return if data_export.revoked?

        data_export.archive.attach(
          io: result.value.fetch(:io),
          filename: "mcweb-data-#{data_export.public_id}.zip",
          content_type: "application/zip"
        )
        data_export.update!(
          status: :completed,
          completed_at: Time.current,
          expires_at: RETENTION.from_now,
          manifest: result.value.fetch(:manifest),
          error_code: nil
        )
      end
    rescue StandardError => e
      mark_failed(data_export, e)
    end

    private

    def mark_failed(data_export, error)
      return unless data_export&.persisted?

      data_export.with_lock do
        return if data_export.revoked?

        data_export.update!(
          status: :failed,
          failed_at: Time.current,
          error_code: error.is_a?(ExportFailed) ? error.message : "data_export_generation_failed"
        )
      end
    rescue ActiveRecord::RecordNotFound
      nil
    end

    class ExportFailed < StandardError; end
  end
end

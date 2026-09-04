# frozen_string_literal: true

module Identity
  class BuildDataExportJob < ApplicationJob
    queue_as :default

    RETENTION = 72.hours
    RUNNING_LEASE = 1.hour

    def self.stale_running?(data_export, at: Time.current)
      data_export.running? && (
        data_export.started_at.blank? || data_export.started_at <= at - RUNNING_LEASE
      )
    end

    def perform(data_export_id, expected_request_revision = nil)
      archive_io = nil
      staged_blob = nil
      generation_completed = false
      generation_attempt = nil
      data_export = DataExport.find_by(id: data_export_id)
      return unless data_export

      data_export.with_lock do
        return unless request_revision_matches?(data_export, expected_request_revision)
        return unless data_export.queued? || self.class.stale_running?(data_export)

        generation_attempt = data_export.attempts + 1
        data_export.update!(
          status: :running,
          started_at: Time.current,
          attempts: generation_attempt,
          failed_at: nil,
          error_code: nil
        )
      end
      return unless generation_attempt

      result = DataExportArchive.call(user: data_export.user)
      raise ExportFailed, result.code unless result.success?
      archive_io = result.value.fetch(:io)
      staged_blob = stage_archive_blob(data_export, archive_io, generation_attempt:)

      data_export.with_lock do
        return unless request_revision_matches?(data_export, expected_request_revision)
        return unless data_export.running? && data_export.attempts == generation_attempt

        data_export.archive.attach(staged_blob)
        data_export.update!(
          status: :completed,
          completed_at: Time.current,
          expires_at: RETENTION.from_now,
          manifest: result.value.fetch(:manifest),
          error_code: nil
        )
      end
      generation_completed = true
    rescue NoMemoryError, SystemStackError
      mark_failed(
        data_export,
        ExportFailed.new("data_export_resource_exhausted"),
        generation_attempt:
      )
    rescue StandardError => e
      mark_failed(data_export, e, generation_attempt:)
    ensure
      cleanup_archive_io(archive_io)
      cleanup_staged_blob(staged_blob) unless generation_completed
    end

    private

    def stage_archive_blob(data_export, archive_io, generation_attempt:)
      blob = ActiveStorage::Blob.build_after_unfurling(
        io: archive_io,
        filename: "mcweb-data-#{data_export.public_id}.zip",
        content_type: "application/zip",
        metadata: {
          "identity_data_export_staging" => true,
          "data_export_public_id" => data_export.public_id,
          "data_export_request_revision" => Identity::DataExportGeneration.request_revision(data_export),
          "data_export_generation_attempt" => generation_attempt
        },
        identify: false
      )
      blob.save!
      archive_io.rewind
      blob.upload_without_unfurling(archive_io)
      blob
    rescue StandardError, NoMemoryError, SystemStackError
      cleanup_staged_blob(blob)
      raise
    end

    def request_revision_matches?(data_export, expected_request_revision)
      expected_request_revision.blank? ||
        Identity::DataExportGeneration.request_revision(data_export) == expected_request_revision
    end

    def mark_failed(data_export, error, generation_attempt:)
      return unless data_export&.persisted? && generation_attempt

      data_export.with_lock do
        return unless data_export.running? && data_export.attempts == generation_attempt

        data_export.update!(
          status: :failed,
          failed_at: Time.current,
          error_code: error.is_a?(ExportFailed) ? error.message : "data_export_generation_failed"
        )
      end
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def cleanup_archive_io(io)
      return unless io

      io.close
      io.unlink if io.respond_to?(:unlink)
    rescue StandardError
      nil
    end

    def cleanup_staged_blob(blob)
      Identity::DataExportBlobCleanup.purge_now(blob)
    end

    class ExportFailed < StandardError; end
  end
end

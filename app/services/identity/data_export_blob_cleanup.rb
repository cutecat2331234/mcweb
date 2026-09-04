# frozen_string_literal: true

module Identity
  module DataExportBlobCleanup
    STAGED_ORPHAN_AFTER = 2.hours
    BATCH_SIZE = 100
    STAGING_METADATA_KEY = "identity_data_export_staging"
    CLEANUP_LOCK_NAME = "identity.data-export-staged-blob-cleanup.v1"
    CLEANUP_CURSOR_NAME = "staged-data-export-blobs.v1"

    module_function

    def purge_now(blob)
      return false unless purgeable?(blob)

      removed = false
      blob.with_lock do
        next if blob.attachments.exists?

        # Active Storage destroys the locator before deleting the object. A
        # storage failure can therefore leave an untraceable private object.
        # Keep the row locked until remote deletion succeeds, then remove it.
        blob.delete
        blob.destroy!
        removed = true
      end
      removed
    rescue ActiveRecord::RecordNotFound
      true
    rescue StandardError => error
      log_failure("purge", blob, error)
      false
    end

    def purge_later(blob)
      return false unless purgeable?(blob)

      mark_for_cleanup!(blob)
      job = Identity::PurgeDataExportBlobJob.perform_later(blob.id)
      job&.successfully_enqueued? == true
    rescue StandardError => error
      log_failure("purge_schedule", blob, error)
      false
    end

    def cleanup_staged!(now: Time.current, older_than: STAGED_ORPHAN_AFTER, limit: BATCH_SIZE)
      cutoff = now - normalized_age(older_than)
      result = { scanned: 0, removed: 0, retained: 0, failed: 0 }

      execution = Operations::ExclusiveExecution.try_with(name: CLEANUP_LOCK_NAME) do
        cleanup_staged_batch!(
          result:,
          cutoff:,
          now:,
          limit: normalized_limit(limit)
        )
      end

      (execution.acquired? ? execution.value : result).freeze
    end

    def cleanup_staged_batch!(result:, cutoff:, now:, limit:)
      cursor = cleanup_cursor
      blobs = next_staged_batch(cursor:, cutoff:, limit:)

      blobs.each do |blob|
        begin
          next unless staged_blob?(blob)

          result[:scanned] += 1
          if live_generation_owner?(blob, now:)
            result[:retained] += 1
          elsif purge_now(blob)
            result[:removed] += 1
          else
            result[:failed] += 1
          end
        rescue StandardError => error
          result[:failed] += 1
          log_failure("orphan_inspection", blob, error)
        end
      end

      cursor.update!(last_blob_id: blobs.last.id) if blobs.any?
      result
    end
    private_class_method :cleanup_staged_batch!

    def purgeable?(blob)
      blob&.persisted? && !blob.attachments.exists?
    end
    private_class_method :purgeable?

    def mark_for_cleanup!(blob)
      blob.with_lock do
        raise ActiveRecord::InvalidForeignKey if blob.attachments.exists?

        metadata = blob.metadata.to_h.merge(STAGING_METADATA_KEY => true)
        # Internal cleanup metadata must not trigger an object-store metadata
        # rewrite while the object is about to be deleted.
        blob.update_columns(metadata:)
      end
    end
    private_class_method :mark_for_cleanup!

    def cleanup_cursor
      Identity::DataExportBlobCleanupCursor.find_or_create_by!(
        name: CLEANUP_CURSOR_NAME
      )
    end
    private_class_method :cleanup_cursor

    def next_staged_batch(cursor:, cutoff:, limit:)
      scope = staged_scope(cutoff:)
      batch = batch_in_current_cycle(scope:, cursor:, limit:)
      return batch if batch.any?

      start_new_cycle!(cursor:, scope:)
      batch_in_current_cycle(scope:, cursor:, limit:)
    end
    private_class_method :next_staged_batch

    def batch_in_current_cycle(scope:, cursor:, limit:)
      return [] unless cursor.cycle_max_blob_id.positive?

      scope
        .where(id: (cursor.last_blob_id + 1)..cursor.cycle_max_blob_id)
        .order(:id)
        .limit(limit)
        .to_a
    end
    private_class_method :batch_in_current_cycle

    def start_new_cycle!(cursor:, scope:)
      cycle_max_blob_id = scope.maximum(:id).to_i
      cursor.update!(last_blob_id: 0, cycle_max_blob_id:)
    end
    private_class_method :start_new_cycle!

    def staged_scope(cutoff:)
      ActiveStorage::Blob.unattached
        .where(
          "(COALESCE(NULLIF(active_storage_blobs.metadata, ''), '{}')::jsonb -> ?) = 'true'::jsonb",
          STAGING_METADATA_KEY
        )
        .where("active_storage_blobs.created_at <= ?", cutoff)
    end
    private_class_method :staged_scope

    def staged_blob?(blob)
      blob.metadata.to_h[STAGING_METADATA_KEY] == true
    end
    private_class_method :staged_blob?

    def live_generation_owner?(blob, now:)
      metadata = blob.metadata.to_h
      data_export = Identity::DataExport.find_by(
        public_id: metadata["data_export_public_id"].to_s
      )
      return false unless data_export&.running?

      revision = metadata["data_export_request_revision"].to_s
      attempt = Integer(metadata["data_export_generation_attempt"], exception: false)
      return false if revision.blank? || attempt.blank?
      return false if revision != Identity::DataExportGeneration.request_revision(data_export)
      return false if attempt != data_export.attempts

      Identity::DataExportGeneration.live_execution?(data_export, now:)
    end
    private_class_method :live_generation_owner?

    def normalized_age(value)
      seconds = value.to_i
      raise ArgumentError, "data_export_staged_blob_retention_invalid" unless seconds.positive?

      seconds.seconds
    end
    private_class_method :normalized_age

    def normalized_limit(value)
      Integer(value, exception: false)&.clamp(1, 1_000) || BATCH_SIZE
    end
    private_class_method :normalized_limit

    def log_failure(operation, blob, error)
      Rails.logger.warn(
        "[identity.data_export] blob_#{operation}_failed " \
          "blob_id=#{blob&.id} error=#{error.class}"
      )
    end
    private_class_method :log_failure
  end
end

# frozen_string_literal: true

require "stringio"
require "timeout"

module SecureEvidence
  class StoreAttachmentUpload < ApplicationService
    class StaleAttempt < StandardError; end

    REMOTE_UPLOAD_TIMEOUT = 10.minutes
    WRITER_LEASE = 1.hour

    def initialize(attachment:, upload:, payload:, filename:, content_type:, at: Time.current)
      @attachment = attachment
      @upload = upload
      @payload = payload.to_s.b
      @sha256 = Digest::SHA256.hexdigest(@payload)
      @filename = filename
      @content_type = content_type
      @at = at
      @blob = nil
      @upload_attempt = upload.cleanup_attempts
      @remote_upload_started = false
    end

    def call
      caller_connection = ApplicationRecord.connection_pool.active_connection
      io = StringIO.new(@payload)
      @blob = ActiveStorage::Blob.build_after_unfurling(
        io:,
        filename: @filename,
        content_type: @content_type,
        identify: false
      )
      persist_tracked_blob!
      release_storage_database_lease!(caller_connection)
      ensure_remote_io_without_database_lease!

      io.rewind
      @remote_upload_started = true
      Timeout.timeout(REMOTE_UPLOAD_TIMEOUT) do
        @blob.upload_without_unfurling(io)
      end
      finalize_upload!

      instrument_success
      ServiceResult.success(attachment: @attachment, upload: @upload, blob: @blob)
    rescue StandardError => error
      recovery = reconcile_after_storage_error(error)
      if recovery == :committed
        instrument_success
        return ServiceResult.success(
          attachment: @attachment,
          upload: @upload,
          blob: @blob,
          commit_reconciled: true
        )
      end

      delete_orphaned_remote_object
      Rails.logger.error(
        "[SecureEvidence::StoreAttachmentUpload] failed " \
        "attachment_id=#{@attachment.id} upload_id=#{@upload.id} error=#{error.class}"
      )
      ServiceResult.failure(
        error: "secure_evidence_upload_failed",
        code: "secure_evidence_upload_failed",
        value: { attachment: @attachment, retryable: true }
      )
    end

    private

    def ensure_remote_io_without_database_lease!
      connection = ApplicationRecord.connection_pool.active_connection
      return unless connection
      # Transactional test fixtures pin a deliberately isolated connection for
      # the whole example. They do not represent an application-owned lease;
      # the non-transactional concurrency suite covers the production contract.
      return if Rails.env.test? && connection.pinned &&
        !connection.current_transaction.joinable?

      # A nested service never owns a lease that was already checked out by
      # its caller. Refuse remote I/O instead of returning that connection to
      # the pool while the caller can still use it.
      raise ActiveRecord::ActiveRecordError,
        if connection.transaction_open?
          "secure_evidence_remote_upload_transaction_open"
        else
          "secure_evidence_remote_upload_connection_leased"
        end
    end

    def persist_tracked_blob!
      Community::Upload.transaction do
        lock_current_attempt!
        unless attempt_matches? && @attachment.state_uploading? &&
            @upload.status_reserved? && @upload.blob.nil?
          raise StaleAttempt, "secure_evidence_upload_attempt_not_reserved"
        end

        @blob.save!
        @upload.update!(
          blob: @blob,
          # This is a single guarded lease acquisition immediately before the
          # real PUT, not a heartbeat. It guarantees the hard upload timeout
          # always has a wide cleanup margin even after scheduler delay.
          expires_at: WRITER_LEASE.from_now
        )
      end
    end

    def finalize_upload!
      Community::Upload.transaction do
        lock_current_attempt!
        unless attempt_matches? && @attachment.state_uploading? &&
            @upload.status_reserved? &&
            @upload.active_storage_blob_id == @blob.id
          raise StaleAttempt, "secure_evidence_upload_attempt_stale"
        end

        @upload.stored!(
          blob: @blob,
          expires_at: Community::StoreUpload::PENDING_TTL.from_now
        )
        @attachment = SyncUploadResult.stored!(
          attachment: @attachment,
          upload: @upload,
          at: @at
        )
      end
    end

    def lock_current_attempt!
      @upload.lock!
      @attachment.lock!
      return if @upload.secure_evidence_attachment_id == @attachment.id

      raise StaleAttempt, "secure_evidence_upload_attempt_replaced"
    end

    def attempt_matches?
      @upload.kind_secure_evidence_attachment? &&
        @upload.cleanup_attempts == @upload_attempt &&
        @upload.user_id == @attachment.uploader_id &&
        @upload.byte_size == @attachment.byte_size &&
        @payload.bytesize == @attachment.byte_size &&
        @sha256 == @attachment.sha256 &&
        @filename == @attachment.filename &&
        @content_type == @attachment.content_type
    end

    def reconcile_after_storage_error(error)
      upload_id = nil
      outcome = :stale
      Community::Upload.transaction do
        @upload.lock!
        @attachment.lock!

        if committed_attempt?
          outcome = :committed
          next
        end

        if discarded_attempt_current?
          # Discard deliberately retained the lease while the PUT was in
          # flight. This exact writer has now returned, so cleanup can resume.
          now = Time.current
          @upload.update!(expires_at: [ @upload.expires_at, now ].compact.min)
          upload_id = @upload.id
          outcome = :cleanup_scheduled
          next
        end

        next unless failed_attempt_current?

        if @attachment.state_uploading? && @upload.status_reserved?
          @attachment = SyncUploadResult.failed!(
            attachment: @attachment,
            upload: @upload,
            failure_code: error.class.name,
            at: @at
          )
        end
        @upload.request_cleanup!(error:, at: failure_cleanup_due_at)
        upload_id = @upload.id
        outcome = :cleanup_scheduled
      end
      enqueue_cleanup(upload_id) if upload_id
      outcome
    rescue StandardError => cleanup_error
      Rails.logger.error(
        "[SecureEvidence::StoreAttachmentUpload] storage reconciliation failed " \
        "attachment_id=#{@attachment.id} upload_id=#{@upload.id} " \
        "error=#{cleanup_error.class}"
      )
      :stale
    end

    def committed_attempt?
      exact_blob_attempt? &&
        @upload.status_stored? &&
        @attachment.state_pending?
    end

    def discarded_attempt_current?
      exact_blob_attempt? &&
        @upload.status_cleanup_pending? &&
        @attachment.state_purge_pending?
    end

    def failed_attempt_current?
      exact_blob_attempt? &&
        @upload.status_reserved? &&
        @attachment.state_uploading?
    end

    def exact_blob_attempt?
      attempt_matches? &&
        @upload.secure_evidence_attachment_id == @attachment.id &&
        @upload.active_storage_blob_id == @blob&.id
    end

    def failure_cleanup_due_at
      now = Time.current
      return now unless @remote_upload_started && @upload.expires_at

      [ now, @upload.expires_at ].max
    end

    def enqueue_cleanup(upload_id)
      Maintenance::CleanupForumUploadsJob.perform_later(upload_id:)
    rescue StandardError => error
      Rails.logger.error(
        "[SecureEvidence::StoreAttachmentUpload] cleanup enqueue deferred " \
        "upload_id=#{upload_id} error=#{error.class}"
      )
    end

    def release_storage_database_lease!(caller_connection)
      return if caller_connection

      pool = ApplicationRecord.connection_pool
      connection = pool.active_connection
      return unless connection

      if connection.transaction_open?
        raise ActiveRecord::ActiveRecordError,
          "secure_evidence_remote_upload_transaction_open"
      end

      pool.release_connection
    end

    def delete_orphaned_remote_object
      return unless @remote_upload_started && @blob&.key
      tracked = ApplicationRecord.with_connection do
        ActiveStorage::Blob.where(id: @blob.id).exists? ||
          Community::Upload.where(active_storage_blob_id: @blob.id).exists? ||
          ActiveStorage::Attachment.where(blob_id: @blob.id).exists?
      end
      return if tracked

      ensure_remote_io_without_database_lease!
      # A cleanup generation may have removed the durable blob row while an
      # expired writer was still returning from object storage. Only that
      # row-less, unaddressable key is safe to delete synchronously. Tracked
      # blobs always stay on the durable cleanup path.
      @blob.delete
    rescue StandardError => error
      Rails.logger.error(
        "[SecureEvidence::StoreAttachmentUpload] late blob cleanup deferred " \
        "blob_id=#{@blob&.id} error=#{error.class}"
      )
    end

    def instrument_success
      ActiveSupport::Notifications.instrument(
        "community.upload.stored",
        upload_id: @upload.id,
        user_id: @upload.user_id,
        kind: @upload.kind,
        blob_id: @blob.id,
        byte_size: @payload.bytesize
      )
      ActiveSupport::Notifications.instrument(
        "secure_evidence.upload.stored",
        attachment_id: @attachment.id,
        upload_id: @upload.id,
        blob_id: @blob.id,
        byte_size: @payload.bytesize
      )
    rescue StandardError => error
      Rails.logger.warn(
        "[SecureEvidence::StoreAttachmentUpload] instrumentation failed " \
        "upload_id=#{@upload.id} error=#{error.class}"
      )
    end
  end
end

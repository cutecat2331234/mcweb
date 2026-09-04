# frozen_string_literal: true

module Community
  class CleanupUpload < ApplicationService
    def initialize(upload:, force: false, orphan_only: false, now: Time.current)
      @upload = upload
      @force = force
      @orphan_only = orphan_only
      @now = now
    end

    def call
      snapshot = nil
      claim = claim_cleanup
      return claim if claim.failure? || claim.value[:skipped]

      snapshot = claim.value
      remove_attachment(snapshot[:post_attachment_id])
      purge_blob(snapshot[:blob_id])
      finish_cleanup(snapshot)
    rescue StandardError => error
      record_failure(error, snapshot:)
      ServiceResult.failure(
        error: "upload_cleanup_failed",
        code: "upload_cleanup_failed",
        value: { upload_id: @upload.id, retryable: true }
      )
    end

    private

    def claim_cleanup
      snapshot = nil
      skipped = nil

      Community::Upload.transaction do
        attachment = lock_attachment
        @upload.lock!
        secure_evidence_attachment = lock_secure_evidence_attachment

        if @upload.status_cleaned?
          skipped = "already_cleaned"
          next
        end

        if @orphan_only && (!attachment || attachment.linked?)
          skipped = "not_orphan"
          next
        end

        if attachment&.linked? && !@force && !@upload.scan_quarantined?
          @upload.update!(
            status: "linked",
            post: attachment.post,
            expires_at: nil,
            cleanup_started_at: nil
          )
          skipped = "linked_attachment"
          next
        end

        unless cleanup_allowed?(secure_evidence_attachment:)
          skipped = "not_due"
          next
        end

        mark_expired_upload_failed!(secure_evidence_attachment)

        @upload.update!(
          status: "cleanup_pending",
          cleanup_started_at: @now,
          cleanup_attempts: @upload.cleanup_attempts + 1,
          cleanup_error_code: nil,
          cleanup_error_message: nil
        )
        snapshot = {
          post_attachment_id: attachment&.id,
          secure_evidence_attachment_id: secure_evidence_attachment&.id,
          blob_id: @upload.active_storage_blob_id,
          cleanup_attempt: @upload.cleanup_attempts
        }
      end

      return ServiceResult.success(skipped: skipped) if skipped

      ServiceResult.success(snapshot)
    end

    def lock_attachment
      return unless @upload.forum_post_attachment_id

      Community::PostAttachment
        .lock
        .find_by(id: @upload.forum_post_attachment_id)
    end

    def lock_secure_evidence_attachment
      return unless @upload.kind_secure_evidence_attachment? &&
        @upload.secure_evidence_attachment_id

      SecureEvidence::Attachment.lock.find_by(
        id: @upload.secure_evidence_attachment_id
      )
    end

    def cleanup_allowed?(secure_evidence_attachment:)
      if @upload.kind_secure_evidence_attachment? &&
          @upload.secure_evidence_attachment_id
        return false unless secure_evidence_attachment
        return false if @upload.status_cleanup_pending? &&
          @upload.cleanup_started_at&.>(@now - 30.minutes)

        return false unless @upload.expires_at&.<=(@now)
        if secure_evidence_attachment.state_uploading?
          return @upload.status_reserved? || @upload.status_cleanup_failed?
        end
        return false unless secure_evidence_attachment.state_purge_pending? ||
          secure_evidence_attachment.state_upload_failed?

        return @upload.status_cleanup_pending? || @upload.status_cleanup_failed?
      end
      return true if @orphan_only
      return true if @force
      return true if @upload.scan_quarantined? && @upload.expires_at&.<=(@now)
      return false if @upload.status_linked?
      return true if @upload.status_cleanup_pending? &&
        @upload.cleanup_started_at&.<=(30.minutes.ago)

      @upload.expires_at&.<=(@now)
    end

    def mark_expired_upload_failed!(attachment)
      return unless attachment&.state_uploading?

      SecureEvidence::SyncUploadResult.failed!(
        attachment:,
        upload: @upload,
        failure_code: "secure_evidence_upload_timeout",
        at: @now
      )
    end

    def remove_attachment(attachment_id)
      return unless attachment_id

      attachment = Community::PostAttachment.find_by(id: attachment_id)
      return unless attachment

      attachment.file.detach if attachment.file.attached?
      attachment.destroy!
    end

    def purge_blob(blob_id)
      return unless blob_id

      blob = ApplicationRecord.with_connection do
        ActiveStorage::Blob.find_by(id: blob_id)
      end
      return unless blob
      return if blob.attachments.exists?

      # Keep the blob row and its durable object key until the guarded cleanup
      # transaction commits. A crash after remote deletion can then retry the
      # same key instead of leaving an unaddressable object behind.
      blob.delete
    end

    def finish_cleanup(snapshot)
      blob = nil
      result = nil
      Community::Upload.transaction do
        @upload.lock!
        unless current_cleanup_claim?(snapshot)
          result = ServiceResult.success(
            upload_id: @upload.id,
            cleaned: false,
            skipped: "cleanup_superseded"
          )
          next
        end

        blob = ActiveStorage::Blob.lock.find_by(id: snapshot.fetch(:blob_id)) if
          snapshot[:blob_id]
        secure_evidence_attachment_id = snapshot[:secure_evidence_attachment_id]
        if secure_evidence_attachment_id
          SecureEvidence::SyncCleanupResult.completed!(
            attachment_id: secure_evidence_attachment_id,
            upload: @upload,
            expected_cleanup_attempt: snapshot.fetch(:cleanup_attempt),
            expected_blob_id: snapshot[:blob_id],
            at: @now
          )
        end
        @upload.update!(
          status: "cleaned",
          blob: nil,
          post_attachment: nil,
          post: nil,
          expires_at: nil,
          cleanup_started_at: nil,
          cleaned_at: @now,
          cleanup_error_code: nil,
          cleanup_error_message: nil
        )
        result = ServiceResult.success(upload_id: @upload.id, cleaned: true)
      end
      return result if result.value[:skipped]

      destroy_blob_metadata(blob)
      instrument("community.upload.cleaned")
      result
    end

    def record_failure(error, snapshot:)
      unless snapshot
        Rails.logger.error(
          "[Community::CleanupUpload] cleanup claim failed " \
          "upload_id=#{@upload.id} error=#{error.class}"
        )
        return
      end

      recorded = false
      Community::Upload.transaction do
        @upload.lock!
        next unless current_cleanup_claim?(snapshot)

        if @upload.secure_evidence_attachment_id
          SecureEvidence::SyncCleanupResult.failed!(
            attachment_id: @upload.secure_evidence_attachment_id,
            upload: @upload,
            expected_cleanup_attempt: snapshot.fetch(:cleanup_attempt),
            expected_blob_id: snapshot[:blob_id],
            error:,
            at: @now
          )
        end
        @upload.update!(
          status: "cleanup_failed",
          expires_at: @now,
          cleanup_started_at: nil,
          cleanup_error_code: error.class.name.to_s.first(120),
          cleanup_error_message: error.message.to_s.first(500)
        )
        recorded = true
      end
      return unless recorded

      instrument(
        "community.upload.cleanup_failed",
        error_class: error.class.name,
        attempts: @upload.cleanup_attempts
      )
      Rails.logger.error(
        "[Community::CleanupUpload] failed upload_id=#{@upload.id} " \
        "attempt=#{@upload.cleanup_attempts} error=#{error.class}"
      )
    rescue StandardError => record_error
      Rails.logger.error(
        "[Community::CleanupUpload] failed to record cleanup error " \
        "upload_id=#{@upload.id} error=#{record_error.class}"
      )
    end

    def current_cleanup_claim?(snapshot)
      @upload.status_cleanup_pending? &&
        @upload.cleanup_attempts == snapshot.fetch(:cleanup_attempt) &&
        @upload.active_storage_blob_id == snapshot[:blob_id] &&
        @upload.secure_evidence_attachment_id == snapshot[:secure_evidence_attachment_id]
    end

    def destroy_blob_metadata(blob)
      return unless blob
      return if blob.attachments.exists?
      return if Community::Upload.where(active_storage_blob_id: blob.id).exists?

      blob.destroy!
    rescue StandardError => error
      Rails.logger.warn(
        "[Community::CleanupUpload] blob metadata cleanup deferred " \
        "upload_id=#{@upload.id} blob_id=#{blob&.id} error=#{error.class}"
      )
    end

    def instrument(name, extra = {})
      ActiveSupport::Notifications.instrument(
        name,
        {
          upload_id: @upload.id,
          user_id: @upload.user_id,
          kind: @upload.kind,
          attempts: @upload.cleanup_attempts
        }.merge(extra)
      )
    end
  end
end

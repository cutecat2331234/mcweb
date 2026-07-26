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
      claim = claim_cleanup
      return claim if claim.failure? || claim.value[:skipped]

      snapshot = claim.value
      remove_attachment(snapshot[:post_attachment_id])
      purge_blob(snapshot[:blob_id])
      finish_cleanup
    rescue StandardError => error
      record_failure(error)
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

        if @upload.status_cleaned?
          skipped = "already_cleaned"
          next
        end

        if @orphan_only && (!attachment || attachment.forum_post_id.present?)
          skipped = "not_orphan"
          next
        end

        if attachment&.forum_post_id.present? && !@force && !@upload.scan_quarantined?
          @upload.update!(
            status: "linked",
            post: attachment.post,
            expires_at: nil,
            cleanup_started_at: nil
          )
          skipped = "linked_attachment"
          next
        end

        unless cleanup_allowed?
          skipped = "not_due"
          next
        end

        @upload.update!(
          status: "cleanup_pending",
          cleanup_started_at: @now,
          cleanup_attempts: @upload.cleanup_attempts + 1,
          cleanup_error_code: nil,
          cleanup_error_message: nil
        )
        snapshot = {
          post_attachment_id: attachment&.id,
          blob_id: @upload.active_storage_blob_id
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

    def cleanup_allowed?
      return true if @orphan_only
      return true if @force
      return true if @upload.scan_quarantined? && @upload.expires_at&.<=(@now)
      return false if @upload.status_linked?
      return true if @upload.status_cleanup_pending? &&
        @upload.cleanup_started_at&.<=(30.minutes.ago)

      @upload.expires_at&.<=(@now)
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

      blob = ActiveStorage::Blob.find_by(id: blob_id)
      return unless blob

      blob.purge
    end

    def finish_cleanup
      @upload.with_lock do
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
      end
      instrument("community.upload.cleaned")
      ServiceResult.success(upload_id: @upload.id, cleaned: true)
    end

    def record_failure(error)
      @upload.with_lock do
        @upload.update!(
          status: "cleanup_failed",
          expires_at: @now,
          cleanup_started_at: nil,
          cleanup_error_code: error.class.name.to_s.first(120),
          cleanup_error_message: error.message.to_s.first(500)
        )
      end
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

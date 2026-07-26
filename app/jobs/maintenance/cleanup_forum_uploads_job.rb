# frozen_string_literal: true

module Maintenance
  class CleanupForumUploadsJob < ApplicationJob
    class RetryableCleanupError < StandardError; end

    queue_as :maintenance
    retry_on RetryableCleanupError, wait: :polynomially_longer, attempts: 5

    DEFAULT_BATCH_SIZE = 200
    DEFAULT_LEGACY_RETENTION_HOURS = 24
    DEFAULT_UNATTACHED_RETENTION_HOURS = 168

    def perform(upload_id: nil, now: Time.current, limit: nil)
      failures = []
      if upload_id
        cleanup_upload(Community::Upload.find_by(id: upload_id), failures)
      else
        batch_size = normalized_batch_size(limit)
        adopt_legacy_attachments(now, batch_size)
        Community::Upload.cleanup_due(now).order(:id).limit(batch_size).each do |upload|
          cleanup_upload(upload, failures)
        end
        cleanup_unattached_blobs(now, batch_size, failures)
      end

      return if failures.empty?

      raise RetryableCleanupError,
        "Forum upload cleanup incomplete for #{failures.size} item(s)."
    end

    private

    def cleanup_upload(upload, failures)
      return unless upload

      result = Community::CleanupUpload.call(upload: upload)
      failures << "upload:#{upload.id}" if result.failure?
    end

    def adopt_legacy_attachments(now, limit)
      cutoff = now - configured_hours(
        "forum.upload_cleanup.legacy_unlinked_hours",
        DEFAULT_LEGACY_RETENTION_HOURS
      ).hours
      managed_ids = Community::Upload.where.not(forum_post_attachment_id: nil)
        .select(:forum_post_attachment_id)
      Community::PostAttachment.unlinked
        .where.not(id: managed_ids)
        .where("created_at <= ?", cutoff)
        .order(:id)
        .limit(limit)
        .each do |attachment|
          Community::Upload.create_or_find_by!(post_attachment: attachment) do |upload|
            upload.user = attachment.user
            upload.public_id = Community::Upload.generate_public_id
            upload.kind = "post_attachment"
            upload.status = "stored"
            upload.byte_size = [ attachment.byte_size.to_i, 1 ].max
            upload.blob = attachment.file.blob if attachment.file.attached?
            upload.expires_at = now
          end
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
          Rails.logger.warn(
            "[Maintenance::CleanupForumUploadsJob] legacy adoption skipped " \
            "attachment_id=#{attachment.id} error=#{error.class}"
          )
        end
    end

    def cleanup_unattached_blobs(now, limit, failures)
      cutoff = now - configured_hours(
        "forum.upload_cleanup.unattached_blob_hours",
        DEFAULT_UNATTACHED_RETENTION_HOURS
      ).hours
      managed_blob_ids = Community::Upload.where.not(active_storage_blob_id: nil)
        .select(:active_storage_blob_id)
      ActiveStorage::Blob.unattached
        .where.not(id: managed_blob_ids)
        .where("active_storage_blobs.created_at <= ?", cutoff)
        .order(:id)
        .limit(limit)
        .each do |blob|
          blob.purge
          ActiveSupport::Notifications.instrument(
            "community.upload.unattached_blob_cleaned",
            blob_id: blob.id,
            byte_size: blob.byte_size
          )
        rescue StandardError => error
          failures << "blob:#{blob.id}"
          Rails.logger.error(
            "[Maintenance::CleanupForumUploadsJob] unattached blob purge failed " \
            "blob_id=#{blob.id} error=#{error.class}"
          )
        end
    end

    def normalized_batch_size(value)
      configured = Integer(
        value || SiteSetting.get("forum.upload_cleanup.batch_size", DEFAULT_BATCH_SIZE.to_s),
        exception: false
      )
      configured&.between?(1, 1_000) ? configured : DEFAULT_BATCH_SIZE
    end

    def configured_hours(key, default)
      value = Integer(SiteSetting.get(key, default.to_s), exception: false)
      value&.between?(1, 24 * 365) ? value : default
    end
  end
end

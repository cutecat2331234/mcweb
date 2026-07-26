# frozen_string_literal: true

module Community
  class RetryUploadCleanup < ApplicationService
    def initialize(upload:, now: Time.current)
      @upload = upload
      @now = now
    end

    def call
      @upload.with_lock do
        return invalid_result unless @upload.status_cleanup_failed?

        @upload.update!(expires_at: @now)
      end

      enqueued = enqueue_retry
      ActiveSupport::Notifications.instrument(
        "community.upload.cleanup_retry_requested",
        upload_id: @upload.id,
        user_id: @upload.user_id,
        attempts: @upload.cleanup_attempts,
        enqueued: enqueued
      )
      ServiceResult.success(upload: @upload, enqueued: enqueued)
    rescue ActiveRecord::ActiveRecordError => error
      Rails.logger.error(
        "[Community::RetryUploadCleanup] persistence failed " \
        "upload_id=#{@upload.id} error=#{error.class}"
      )
      ServiceResult.failure(
        error: "attachment_cleanup_retry_failed",
        code: "attachment_cleanup_retry_failed"
      )
    end

    private

    def invalid_result
      ServiceResult.failure(
        error: "attachment_cleanup_retry_not_allowed",
        code: "attachment_cleanup_retry_not_allowed"
      )
    end

    def enqueue_retry
      Maintenance::CleanupForumUploadsJob.perform_later(upload_id: @upload.id)
      true
    rescue StandardError => error
      Rails.logger.error(
        "[Community::RetryUploadCleanup] enqueue failed " \
        "upload_id=#{@upload.id} error=#{error.class}"
      )
      false
    end
  end
end

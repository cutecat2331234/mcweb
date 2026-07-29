# frozen_string_literal: true

module Community
  class RetryUploadScan < ApplicationService
    RETRY_RETENTION = 24.hours

    def initialize(upload:, now: Time.current)
      @upload = upload
      @now = now
    end

    def call
      before_state = nil

      @upload.with_lock do
        return invalid_result("attachment_scan_retry_not_allowed") unless retryable?

        before_state = {
          scan_status: @upload.scan_status,
          scan_result_code: @upload.scan_result_code,
          scan_attempts: @upload.scan_attempts,
          quarantined: @upload.quarantined_at.present?,
          manual_review_status: @upload.manual_review_status,
          manual_review_version: @upload.manual_review_version
        }
        attributes = {
          scan_status: "pending",
          scan_started_at: nil,
          scan_attempts: 0,
          next_scan_at: @now,
          quarantined_at: nil,
          expires_at: [ @upload.expires_at, @now + RETRY_RETENTION ].compact.max,
          scanner: nil,
          scan_result_code: nil,
          scan_error_message: nil
        }
        if @upload.manual_review_status_revoked?
          attributes.merge!(
            manual_review_status: "none",
            manual_review_version: @upload.manual_review_version + 1,
            manual_reviewed_at: nil,
            manual_reviewed_by: nil,
            manual_review_source_result_code: nil,
            manual_review_file_sha256: nil,
            manual_review_revoked_at: nil,
            manual_review_revoked_by: nil
          )
        end
        @upload.update!(attributes)
      end

      enqueued = enqueue_retry
      ActiveSupport::Notifications.instrument(
        "community.attachment.scan_retry_requested",
        upload_id: @upload.id,
        user_id: @upload.user_id,
        enqueued: enqueued
      )
      ServiceResult.success(
        upload: @upload,
        before_state: before_state,
        enqueued: enqueued
      )
    rescue ActiveRecord::ActiveRecordError => error
      Rails.logger.error(
        "[Community::RetryUploadScan] persistence failed " \
        "upload_id=#{@upload.id} error=#{error.class}"
      )
      ServiceResult.failure(
        error: "attachment_scan_retry_failed",
        code: "attachment_scan_retry_failed"
      )
    end

    private

    def retryable?
      @upload.kind_post_attachment? &&
        !@upload.status_cleaned? &&
        (@upload.scan_status_error? || @upload.manual_review_status_revoked?) &&
        @upload.blob.present?
    end

    def invalid_result(code)
      ServiceResult.failure(error: code, code: code)
    end

    def enqueue_retry
      Community::ScanPostAttachmentJob.perform_later(upload_id: @upload.id)
      true
    rescue StandardError => error
      Rails.logger.error(
        "[Community::RetryUploadScan] enqueue failed " \
        "upload_id=#{@upload.id} error=#{error.class}"
      )
      false
    end
  end
end

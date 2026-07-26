# frozen_string_literal: true

require "stringio"

module Community
  class StoreUpload < ApplicationService
    PENDING_TTL = 24.hours

    def initialize(user:, kind:, payload:, filename:, content_type:)
      @user = user
      @kind = kind
      @payload = payload.to_s.b
      @filename = filename
      @content_type = content_type
      @upload = nil
    end

    def call
      quota = Community::UploadQuota.call(
        user: @user,
        kind: @kind,
        byte_size: @payload.bytesize
      )
      return quota if quota.failure?

      @upload = quota.value
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(@payload),
        filename: @filename,
        content_type: @content_type,
        identify: false
      )
      @upload.stored!(blob: blob, expires_at: PENDING_TTL.from_now)

      ActiveSupport::Notifications.instrument(
        "community.upload.stored",
        upload_id: @upload.id,
        user_id: @user.id,
        kind: @kind.to_s,
        blob_id: blob.id,
        byte_size: @payload.bytesize
      )
      ServiceResult.success(upload: @upload, blob: blob)
    rescue ActiveRecord::RecordInvalid => error
      request_cleanup(error)
      ServiceResult.failure(errors: error.record.errors.to_hash)
    rescue StandardError => error
      request_cleanup(error)
      raise
    end

    private

    def request_cleanup(error)
      return unless @upload&.persisted?

      @upload.request_cleanup!(error: error)
      Maintenance::CleanupForumUploadsJob.perform_later(upload_id: @upload.id)
    rescue StandardError => cleanup_error
      Rails.logger.error(
        "[Community::StoreUpload] cleanup scheduling failed upload_id=#{@upload.id} " \
        "error=#{cleanup_error.class}"
      )
    end
  end
end

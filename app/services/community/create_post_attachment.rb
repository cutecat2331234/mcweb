# frozen_string_literal: true

module Community
  class CreatePostAttachment < ApplicationService
    def initialize(user:, file:)
      @user = user
      @file = file
    end

    def call
      unless Community::TrustLevel.can_upload_attachments?(@user)
        return ServiceResult.failure(error: "new_members_cannot_upload_attachments")
      end

      return ServiceResult.failure(error: "upload_file_required") unless @file

      filename = safe_filename(@file.original_filename)
      return ServiceResult.failure(error: "invalid_filename") if filename.blank?

      inspection = Community::AllowedAttachmentTypes.inspect_file(filename: filename, io: @file)
      if inspection.too_large?
        max = ActiveSupport::NumberHelper.number_to_human_size(Community::AllowedAttachmentTypes.max_size)
        return ServiceResult.failure(error: I18n.t("mcweb.services.errors.attachment_too_large", max: max))
      end

      unless inspection.success?
        return ServiceResult.failure(error: "unsupported_attachment_type")
      end

      stored = Community::StoreUpload.call(
        user: @user,
        kind: :post_attachment,
        payload: inspection.payload,
        filename: filename,
        content_type: inspection.content_type
      )
      return stored if stored.failure?

      upload = stored.value.fetch(:upload)
      blob = stored.value.fetch(:blob)
      attachment = nil
      Community::PostAttachment.transaction do
        attachment = Community::PostAttachment.create!(
          user: @user,
          filename: filename,
          content_type: inspection.content_type,
          byte_size: inspection.byte_size
        )
        attachment.file.attach(blob)
        upload.update!(post_attachment: attachment)
      end
      enqueue_scan(upload)

      ServiceResult.success(attachment)
    rescue ActiveRecord::RecordInvalid => e
      request_cleanup(upload, e)
      ServiceResult.failure(errors: e.record.errors.to_hash)
    rescue StandardError => e
      request_cleanup(upload, e)
      raise
    end

    private

    def safe_filename(name)
      base = File.basename(name.to_s)
      base.gsub(/[^\w.\-()\[\] ]+/u, "_").strip.first(180)
    end

    def request_cleanup(upload, error)
      return unless upload&.persisted?

      upload.request_cleanup!(error: error)
      Maintenance::CleanupForumUploadsJob.perform_later(upload_id: upload.id)
    rescue StandardError => cleanup_error
      Rails.logger.error(
        "[Community::CreatePostAttachment] cleanup scheduling failed " \
        "upload_id=#{upload.id} error=#{cleanup_error.class}"
      )
    end

    def enqueue_scan(upload)
      Community::ScanPostAttachmentJob.perform_later(upload_id: upload.id)
    rescue StandardError => error
      Rails.logger.error(
        "[Community::CreatePostAttachment] scan scheduling failed " \
        "upload_id=#{upload.id} error=#{error.class}"
      )
    end
  end
end

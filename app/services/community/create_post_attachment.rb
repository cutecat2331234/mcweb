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

      unless Community::AllowedAttachmentTypes.allowed?(filename: filename, content_type: @file.content_type)
        return ServiceResult.failure(error: "unsupported_attachment_type")
      end

      if @file.size > Community::AllowedAttachmentTypes.max_size
        max = ActiveSupport::NumberHelper.number_to_human_size(Community::AllowedAttachmentTypes.max_size)
        return ServiceResult.failure(error: I18n.t("mcweb.services.errors.attachment_too_large", max: max))
      end

      attachment = Community::PostAttachment.new(
        user: @user,
        filename: filename,
        content_type: @file.content_type,
        byte_size: @file.size
      )

      attachment.file.attach(
        io: @file,
        filename: filename,
        content_type: @file.content_type
      )
      attachment.save!

      ServiceResult.success(attachment)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def safe_filename(name)
      base = File.basename(name.to_s)
      base.gsub(/[^\w.\-()\[\] ]+/u, "_").strip.first(180)
    end
  end
end

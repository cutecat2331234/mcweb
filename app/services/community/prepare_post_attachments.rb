# frozen_string_literal: true

module Community
  class PreparePostAttachments < ApplicationService
    INVALID_ERROR = "attachment_invalid_or_unauthorized"

    def initialize(user:, attachment_ids:)
      @user = user
      @raw_attachment_ids = Array(attachment_ids)
    end

    def call
      attachment_ids = normalize_attachment_ids
      return ServiceResult.failure(error: INVALID_ERROR) unless attachment_ids
      return ServiceResult.success([]) if attachment_ids.empty?
      return ServiceResult.failure(error: INVALID_ERROR) unless @user

      attachments = Community::PostAttachment
        .lock
        .unlinked
        .where(user: @user, id: attachment_ids)
        .order(:id)
        .to_a

      return ServiceResult.failure(error: INVALID_ERROR) unless attachments.size == attachment_ids.size
      return ServiceResult.failure(error: INVALID_ERROR) unless attachments.all?(&:scan_bindable?)

      ServiceResult.success(attachments)
    end

    private

    def normalize_attachment_ids
      values = @raw_attachment_ids.reject(&:blank?)
      ids = values.map { |value| Integer(value, exception: false) }
      return nil if ids.any? { |id| id.nil? || id <= 0 }

      ids.uniq
    end
  end
end

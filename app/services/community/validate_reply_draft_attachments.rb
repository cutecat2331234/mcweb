# frozen_string_literal: true

module Community
  class ValidateReplyDraftAttachments < ApplicationService
    def initialize(user:, attachment_ids:)
      @user = user
      @attachment_ids = Array(attachment_ids).map(&:to_i).uniq.reject(&:zero?)
    end

    def call
      return ServiceResult.success([]) if @attachment_ids.empty?

      scope = Community::PostAttachment.unlinked.where(user: @user, id: @attachment_ids)
      return ServiceResult.failure(error: "attachment_invalid_or_unauthorized") if scope.count != @attachment_ids.size

      ServiceResult.success(@attachment_ids)
    end
  end
end

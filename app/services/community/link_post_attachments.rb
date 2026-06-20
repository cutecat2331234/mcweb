# frozen_string_literal: true

module Community
  class LinkPostAttachments < ApplicationService
    def initialize(user:, post:, attachment_ids:)
      @user = user
      @post = post
      @attachment_ids = Array(attachment_ids).map(&:to_i).uniq.reject(&:zero?)
    end

    def call
      return ServiceResult.success(linked: 0) if @attachment_ids.empty?

      scope = Community::PostAttachment.unlinked.where(user: @user, id: @attachment_ids)
      return ServiceResult.failure(error: "attachment_invalid_or_unauthorized") if scope.count != @attachment_ids.size

      scope.update_all(forum_post_id: @post.id, updated_at: Time.current)
      ServiceResult.success(linked: @attachment_ids.size)
    end
  end
end

# frozen_string_literal: true

module Community
  class LinkPostAttachments < ApplicationService
    def initialize(user:, post:, attachment_ids:)
      @user = user
      @post = post
      @attachment_ids = Array(attachment_ids).map(&:to_i).uniq.reject(&:zero?)
    end

    def call
      unless attachment_target_available?
        return ServiceResult.failure(error: "attachment_invalid_or_unauthorized")
      end

      return ServiceResult.success(linked: 0) if @attachment_ids.empty?

      scope = Community::PostAttachment.unlinked.where(user: @user, id: @attachment_ids)
      return ServiceResult.failure(error: "attachment_invalid_or_unauthorized") if scope.count != @attachment_ids.size

      scope.update_all(forum_post_id: @post.id, updated_at: Time.current)
      ServiceResult.success(linked: @attachment_ids.size)
    end

    private

    def attachment_target_available?
      return false unless @user && @post
      return false unless @post.user_id == @user.id
      return false if @post.deleted_at.present? || @post.status == "deleted"
      return false if @post.topic.archived_at.present?

      Community::ForumAccess.topic_visible?(topic: @post.topic, user: @user)
    end
  end
end

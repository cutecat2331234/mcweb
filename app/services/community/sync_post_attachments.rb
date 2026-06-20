# frozen_string_literal: true

module Community
  class SyncPostAttachments < ApplicationService
    def initialize(user:, post:, attachment_ids:)
      @user = user
      @post = post
      @attachment_ids = Array(attachment_ids).map(&:to_i).uniq.reject(&:zero?)
    end

    def call
      return ServiceResult.failure(error: "attachment_unauthorized") unless can_manage_attachments?

      current_ids = @post.attachments.pluck(:id)
      to_link_ids = @attachment_ids - current_ids
      to_unlink_ids = current_ids - @attachment_ids

      if to_link_ids.any?
        link_result = link_new_attachments(to_link_ids)
        return link_result if link_result.failure?
      end

      if to_unlink_ids.any?
        unlink_result = unlink_attachments(to_unlink_ids)
        return unlink_result if unlink_result.failure?
      end

      ServiceResult.success(
        linked: to_link_ids.size,
        unlinked: to_unlink_ids.size,
        changed: to_link_ids.any? || to_unlink_ids.any?
      )
    end

    private

    def can_manage_attachments?
      return true if @user.id == @post.user_id
      return true if @user.permission?("forum.topics.lock")
      return true if Community::SectionModeration.can_moderate_topic?(user: @user, topic: @post.topic)

      false
    end

    def link_new_attachments(to_link_ids)
      if @user.id == @post.user_id
        Community::LinkPostAttachments.call(user: @user, post: @post, attachment_ids: to_link_ids)
      else
        ServiceResult.failure(error: "attachment_invalid_or_unauthorized")
      end
    end

    def unlink_attachments(to_unlink_ids)
      scope = @post.attachments.where(id: to_unlink_ids)
      return ServiceResult.failure(error: "attachment_invalid") if scope.count != to_unlink_ids.size

      scope.update_all(forum_post_id: nil, updated_at: Time.current)
      ServiceResult.success(unlinked: to_unlink_ids.size)
    end
  end
end

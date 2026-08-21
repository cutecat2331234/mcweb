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
        return ServiceResult.failure(
          error: "attachment_invalid_or_unauthorized",
          code: "attachment_invalid_or_unauthorized"
        )
      end

      return ServiceResult.success(linked: 0) if @attachment_ids.empty?

      linked_count = 0
      Community::PostAttachment.transaction do
        attachments = Community::PostAttachment
          .lock
          .unlinked
          .where(user: @user, id: @attachment_ids)
          .to_a
        raise ActiveRecord::Rollback if attachments.size != @attachment_ids.size
        raise ActiveRecord::Rollback unless attachments.all?(&:scan_bindable?)

        linked_count = Community::PostAttachment
          .where(id: attachments.map(&:id), forum_post_id: nil)
          .update_all(forum_post_id: @post.id, updated_at: Time.current)
        raise ActiveRecord::Rollback if linked_count != @attachment_ids.size

        upload_count = Community::Upload
          .where(forum_post_attachment_id: attachments.map(&:id))
          .where(scan_status: "clean", status: "stored")
          .update_all(
            status: "linked",
            forum_post_id: @post.id,
            expires_at: nil,
            cleanup_started_at: nil,
            cleanup_error_code: nil,
            cleanup_error_message: nil,
            updated_at: Time.current
          )
        if upload_count != @attachment_ids.size
          linked_count = 0
          raise ActiveRecord::Rollback
        end
      end

      if linked_count != @attachment_ids.size
        return ServiceResult.failure(
          error: "attachment_invalid_or_unauthorized",
          code: "attachment_invalid_or_unauthorized"
        )
      end

      ServiceResult.success(linked: linked_count)
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

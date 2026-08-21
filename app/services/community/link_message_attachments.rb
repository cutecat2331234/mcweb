# frozen_string_literal: true

module Community
  class LinkMessageAttachments < ApplicationService
    MAX_ATTACHMENTS = 10

    def initialize(user:, message:, attachment_ids:)
      @user = user
      @message = message
      @raw_attachment_ids = Array(attachment_ids)
      @attachment_ids = @raw_attachment_ids.filter_map { |id| Integer(id, exception: false) }.uniq
    end

    def call
      return failure unless target_available?
      return failure unless @attachment_ids.size == @raw_attachment_ids.size
      return failure if @attachment_ids.size > MAX_ATTACHMENTS
      return ServiceResult.success(linked: 0) if @attachment_ids.empty?

      linked_count = 0
      Community::PostAttachment.transaction(requires_new: true) do
        attachments = Community::PostAttachment
          .lock
          .unlinked
          .where(user: @user, id: @attachment_ids)
          .to_a
        raise ActiveRecord::Rollback unless attachments.size == @attachment_ids.size
        raise ActiveRecord::Rollback unless attachments.all?(&:scan_bindable?)

        linked_count = Community::PostAttachment
          .where(id: attachments.map(&:id), forum_post_id: nil, forum_message_id: nil)
          .update_all(forum_message_id: @message.id, updated_at: Time.current)
        raise ActiveRecord::Rollback unless linked_count == @attachment_ids.size

        uploads_updated = Community::Upload
          .where(forum_post_attachment_id: attachments.map(&:id), scan_status: "clean", status: "stored")
          .update_all(
            status: "linked",
            forum_post_id: nil,
            expires_at: nil,
            cleanup_started_at: nil,
            cleanup_error_code: nil,
            cleanup_error_message: nil,
            updated_at: Time.current
          )
        unless uploads_updated == @attachment_ids.size
          linked_count = 0
          raise ActiveRecord::Rollback
        end
      end

      return failure unless linked_count == @attachment_ids.size

      ServiceResult.success(linked: linked_count)
    end

    private

    def target_available?
      @user&.persisted? &&
        @message&.persisted? &&
        @message.user_id == @user.id &&
        !@message.deleted? &&
        @message.conversation.participant?(@user)
    end

    def failure
      ServiceResult.failure(
        error: "attachment_invalid_or_unauthorized",
        code: "attachment_invalid_or_unauthorized"
      )
    end
  end
end

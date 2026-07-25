# frozen_string_literal: true

module Community
  class SaveReplyDraft < ApplicationService
    def initialize(user:, topic:, body:, attachment_ids: nil)
      @user = user
      @topic = topic
      @body = body.to_s
      @attachment_ids = attachment_ids
    end

    def call
      unless Community::ForumAccess.topic_visible?(topic: @topic, user: @user)
        return ServiceResult.failure(error: "Topic not available.")
      end

      state_error = topic_reply_state_error
      return ServiceResult.failure(error: state_error) if state_error

      unless @topic.section.allowed?(@user, :reply)
        return ServiceResult.failure(error: "You are not allowed to reply in this section.")
      end

      unless @topic.section.trust_allowed?(@user, :reply)
        return ServiceResult.failure(error: "Your trust level is too low to reply in this section.")
      end

      unless @topic.section.writable_by?(@user, :reply)
        return ServiceResult.failure(error: "This section is read-only.")
      end

      if Community::TopicReplyBan.active.exists?(forum_topic_id: @topic.id, user_id: @user.id)
        return ServiceResult.failure(error: I18n.t("mcweb.services.errors.topic_reply_banned"))
      end

      attachment_result = Community::ValidateReplyDraftAttachments.call(user: @user, attachment_ids: @attachment_ids)
      return attachment_result if attachment_result.failure?
      validated_attachment_ids = attachment_result.value

      if @body.strip.blank? && validated_attachment_ids.empty?
        Community::ReplyDraft.where(user: @user, topic: @topic).delete_all
        return ServiceResult.success(nil)
      end

      draft = Community::ReplyDraft.find_or_initialize_by(user: @user, topic: @topic)
      draft.body = @body
      draft.attachment_id_list = validated_attachment_ids
      draft.save!
      ServiceResult.success(draft)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def topic_reply_state_error
      return "This topic is archived." if @topic.archived_at.present?
      return "This topic is not open for replies." unless @topic.status == "published"

      "This topic is locked." if @topic.locked?
    end
  end
end

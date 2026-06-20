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
      return ServiceResult.failure(error: "Topic not available.") unless PollParticipation.visible?(topic: @topic, user: @user)

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
  end
end

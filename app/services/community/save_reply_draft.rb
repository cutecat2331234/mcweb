# frozen_string_literal: true

module Community
  class SaveReplyDraft < ApplicationService
    def initialize(user:, topic:, body:)
      @user = user
      @topic = topic
      @body = body.to_s
    end

    def call
      return ServiceResult.failure(error: "Topic not available.") unless PollParticipation.visible?(topic: @topic, user: @user)

      if @body.strip.blank?
        Community::ReplyDraft.where(user: @user, topic: @topic).delete_all
        return ServiceResult.success(nil)
      end

      draft = Community::ReplyDraft.find_or_initialize_by(user: @user, topic: @topic)
      draft.body = @body
      draft.save!
      ServiceResult.success(draft)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

# frozen_string_literal: true

module Community
  class SaveMessageDraft < ApplicationService
    def initialize(user:, conversation:, body:)
      @user = user
      @conversation = conversation
      @body = body.to_s
    end

    def call
      unless @conversation.participant?(@user)
        return ServiceResult.failure(error: "Conversation not available.")
      end

      if @body.strip.blank?
        Community::MessageDraft.where(user: @user, conversation: @conversation).delete_all
        return ServiceResult.success(nil)
      end

      draft = Community::MessageDraft.find_or_initialize_by(user: @user, conversation: @conversation)
      draft.body = @body
      draft.save!
      ServiceResult.success(draft)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

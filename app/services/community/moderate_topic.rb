# frozen_string_literal: true

module Community
  class ModerateTopic < ApplicationService
    def initialize(user:, topic:, action:)
      @user = user
      @topic = topic
      @action = action.to_s
    end

    def call
      unless @user.permission?("forum.topics.lock")
        return ServiceResult.failure(error: "You are not authorized to moderate this topic.")
      end

      case @action
      when "lock"
        @topic.lock_topic!
      when "unlock"
        @topic.unlock_topic!
      when "pin"
        @topic.update!(pinned: true)
      when "unpin"
        @topic.update!(pinned: false)
      else
        return ServiceResult.failure(error: "Unknown moderation action.")
      end

      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

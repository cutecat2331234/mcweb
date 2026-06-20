# frozen_string_literal: true

module Community
  class UnbanTopicReply < ApplicationService
    def initialize(actor:, topic:, user:)
      @actor = actor
      @topic = topic
      @user = user
    end

    def call
      unless @actor.permission?("forum.topics.lock")
        return ServiceResult.failure(error: "unban_reply_unauthorized")
      end

      ban = Community::TopicReplyBan.find_by(topic: @topic, user: @user)
      ban&.destroy!

      ServiceResult.success
    end
  end
end

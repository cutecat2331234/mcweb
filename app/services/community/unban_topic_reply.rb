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
        return ServiceResult.failure(error: "无权解除回复禁言。")
      end

      ban = Community::TopicReplyBan.find_by(topic: @topic, user: @user)
      ban&.destroy!

      ServiceResult.success
    end
  end
end

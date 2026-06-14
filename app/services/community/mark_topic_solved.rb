# frozen_string_literal: true

module Community
  class MarkTopicSolved < ApplicationService
    def initialize(user:, topic:, post:)
      @user = user
      @topic = topic
      @post = post
    end

    def call
      unless can_mark?
        return ServiceResult.failure(error: "You are not allowed to mark this topic as solved.")
      end

      if @post.forum_topic_id != @topic.id
        return ServiceResult.failure(error: "Post does not belong to this topic.")
      end

      @topic.update!(solved_post: @post)
      Community::NotifyTopicSolved.call(topic: @topic, post: @post, actor: @user)
      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def can_mark?
      return true if @user.permission?("forum.topics.lock")

      @user.id == @topic.user_id
    end
  end
end

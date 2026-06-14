# frozen_string_literal: true

module Community
  class RestorePost < ApplicationService
    def initialize(actor:, post:)
      @actor = actor
      @post = post
    end

    def call
      return ServiceResult.failure(error: "无权恢复帖子。") unless can_restore?
      return ServiceResult.failure(error: "帖子未被删除。") unless discarded_post?

      topic = @post.topic
      Community::Post.transaction do
        @post.restore!
        Community::SyncTopicLastPost.call(topic: topic)
      end

      ServiceResult.success(@post)
    end

    private

    def can_restore?
      return false unless discarded_post?
      return true if @actor.permission?("forum.topics.lock")
      return true if @actor.permission?("admin.access")

      false
    end

    def discarded_post?
      @post.deleted_at.present?
    end
  end
end

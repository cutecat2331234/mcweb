# frozen_string_literal: true

module Community
  class RestorePost < ApplicationService
    def initialize(actor:, post:)
      @actor = actor
      @post = post
    end

    def call
      return ServiceResult.failure(error: "restore_post_unauthorized") unless can_restore?
      return ServiceResult.failure(error: "post_not_deleted") unless discarded_post?

      topic = @post.topic
      Community::Post.transaction do
        @post.restore!
        Community::SyncTopicLastPost.call(topic: topic)
      end

      Community::DispatchForumEventWebhook.call(event_type: "post.restored", topic: topic, post: @post)
      ServiceResult.success(@post)
    end

    private

    def can_restore?
      return false unless discarded_post?

      Community::SectionModeration.can_moderate_topic?(user: @actor, topic: @post.topic)
    end

    def discarded_post?
      @post.deleted_at.present?
    end
  end
end

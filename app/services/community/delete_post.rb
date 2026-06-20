# frozen_string_literal: true

module Community
  class DeletePost < ApplicationService
    def initialize(actor:, post:)
      @actor = actor
      @post = post
    end

    def call
      return ServiceResult.failure(error: "cannot_delete_first_post") if @post.floor_number == 1
      return ServiceResult.failure(error: "delete_post_unauthorized") unless authorized?

      topic = @post.topic
      @post.soft_delete!
      Community::SyncTopicLastPost.call(topic: topic)
      Community::DispatchForumEventWebhook.call(event_type: "post.deleted", topic: topic, post: @post)
      ServiceResult.success(@post)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

  private

    def authorized?
      return false unless @actor

      @actor.id == @post.user_id || Community::SectionModeration.can_moderate_topic?(user: @actor, topic: @post.topic)
    end
  end
end

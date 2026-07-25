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
      topic.with_lock do
        @post.soft_delete!
        Community::SyncTopicLastPost.call(topic: topic)
      end
      Community::DispatchForumEventWebhook.call(event_type: "post.deleted", topic: topic, post: @post)
      ServiceResult.success(@post)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

  private

    def authorized?
      return false unless @actor

      topic = @post.topic
      return true if Community::SectionModeration.can_moderate_topic?(user: @actor, topic: topic)
      return false if topic.archived_at.present?

      @actor.id == @post.user_id &&
        Community::PostAccess.readable?(post: @post, user: @actor)
    end
  end
end

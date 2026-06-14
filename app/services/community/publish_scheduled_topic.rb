# frozen_string_literal: true

module Community
  class PublishScheduledTopic < ApplicationService
    def initialize(topic:)
      @topic = topic
    end

    def call
      return ServiceResult.failure(error: "Topic is not scheduled.") unless @topic.scheduled_at.present?
      return ServiceResult.failure(error: "Topic is not ready.") unless @topic.scheduled_at <= Time.current
      return ServiceResult.failure(error: "Topic already published.") unless @topic.draft?

      Community::Topic.transaction do
        @topic.update!(
          status: "published",
          scheduled_at: nil,
          last_posted_at: Time.current
        )
        Community::Subscription.subscribe!(@topic.user, @topic)
        Community::ReadState.mark_read!(@topic.user, @topic, floor: 1)
      end

      opening_post = @topic.posts.first
      Community::ProcessMentions.call(body: opening_post.body, author: @topic.user, post: opening_post, topic: @topic) if opening_post
      Community::NotifySectionTopic.call(topic: @topic)
      Community::NotifyFollowedUserTopic.call(topic: @topic)
      if @topic.tags.any?
        Community::NotifyTagTopic.call(topic: @topic, tags: @topic.tags)
      end
      Community::CheckAutoBadges.call(user: @topic.user)

      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

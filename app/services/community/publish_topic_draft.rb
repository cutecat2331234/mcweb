# frozen_string_literal: true

module Community
  class PublishTopicDraft < ApplicationService
    def initialize(user:, topic:)
      @user = user
      @topic = topic
    end

    def call
      return ServiceResult.failure(error: "Not your draft.") unless @topic.user_id == @user.id
      return ServiceResult.failure(error: "Topic is not a draft.") unless @topic.status == "draft"

      post = @topic.posts.first
      return ServiceResult.failure(error: "Draft body is required.") unless post&.body.present?

      unless @topic.section.allowed?(@user, :create_topic)
        return ServiceResult.failure(error: "You are not allowed to create topics in this section.")
      end

      if Community::Mute.muted?(@user, section: @topic.section)
        return ServiceResult.failure(error: "You are muted in this section.")
      end

      if Community::TrustLevel.contains_link?(post.body) && !Community::TrustLevel.can_post_links?(@user)
        return ServiceResult.failure(error: "New members cannot post links. Participate more to unlock this.")
      end

      Community::Topic.transaction do
        @topic.update!(status: "published", last_posted_at: Time.current, last_post_user: @user)
        Community::Subscription.subscribe!(@user, @topic)
        Community::ReadState.mark_read!(@user, @topic, floor: post.floor_number)
      end

      Community::ProcessMentions.call(body: post.body, author: @user, post: post, topic: @topic)
      Community::NotifySectionTopic.call(topic: @topic)
      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

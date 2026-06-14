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

      Community::Topic.transaction do
        @topic.update!(status: "published", last_posted_at: Time.current)
        Community::Subscription.subscribe!(@user, @topic)
        Community::ReadState.mark_read!(@user, @topic, floor: 1)
      end

      Community::NotifySectionTopic.call(topic: @topic)
      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

# frozen_string_literal: true

module Community
  class NotifyTopicSolved < ApplicationService
    def initialize(topic:, post:, actor:)
      @topic = topic
      @post = post
      @actor = actor
    end

    def call
      notify_user(@topic.user) if @topic.user_id != @actor.id

      ServiceResult.success
    end

    private

    def notify_user(user)
      return unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: "forum.topic_solved")

      Notification.notify!(
        user: user,
        notification_type: "forum.topic_solved",
        title: "你的主题已标记为已解决",
        body: @topic.title.truncate(80),
        metadata: {
          topic_id: @topic.public_id,
          post_id: @post.id,
          path: "/forum/topics/#{@topic.public_id}#post-#{@post.id}"
        }
      )
    end
  end
end

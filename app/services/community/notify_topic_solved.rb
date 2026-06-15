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
      email_enabled = NotificationPreference.enabled?(user, channel: "email", notification_type: "forum.topic_solved")
      in_app_enabled = NotificationPreference.enabled?(user, channel: "in_app", notification_type: "forum.topic_solved")
      return unless email_enabled || in_app_enabled

      if in_app_enabled
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

      if email_enabled
        MailDeliveryJob.perform_later(
          "Community::ForumMailer",
          "topic_solved",
          "deliver_now",
          args: [ user.id, @topic.public_id, @post.id, @actor.id ]
        )
      end
    end
  end
end

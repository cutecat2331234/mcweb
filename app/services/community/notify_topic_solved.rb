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
      email_enabled = Community::InstantEmailDelivery.allowed?(user, notification_type: "forum.topic_solved")
      in_app_enabled = NotificationPreference.enabled?(user, channel: "in_app", notification_type: "forum.topic_solved")
      return unless email_enabled || in_app_enabled

      if in_app_enabled
        Community::InAppNotification.notify(
          user: user,
          notification_type: "forum.topic_solved",
          key: "topic_solved",
          title: @topic.title.truncate(80),
          metadata: {
            topic_id: @topic.public_id,
            post_id: @post.id,
            path: Community::PostPermalink.path(@topic, @post)
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

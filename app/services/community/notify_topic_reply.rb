# frozen_string_literal: true

module Community
  class NotifyTopicReply < ApplicationService
    def initialize(post:)
      @post = post
      @topic = post.topic
    end

    def call
      return ServiceResult.success if @topic.unlisted?

      subscriber_ids = Community::Subscription
        .where(subscribable: @topic)
        .where.not(user_id: @post.user_id)
        .pluck(:user_id, :notification_level)

      muted_ids = Community::TopicMute.where(forum_topic_id: @topic.id, user_id: subscriber_ids.map(&:first)).pluck(:user_id)
      recipient_ids = Community::FilterNotificationRecipients.call(
        actor_id: @post.user_id,
        recipient_ids: subscriber_ids.map(&:first) - muted_ids,
        topic: @topic
      ).value

      levels_by_user = subscriber_ids.to_h

      User.where(id: recipient_ids).find_each do |user|
        level = levels_by_user[user.id] || "watching"
        next unless NotificationLevelFilter.deliver_in_app?(
          level: level,
          user: user,
          topic: @topic,
          post: @post,
          context: :topic_reply
        )
        next unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: "forum.topic_reply")

        Community::ReadState.ensure_tracking!(user, @topic)

        Community::InAppNotification.notify(
          user: user,
          notification_type: "forum.topic_reply",
          key: "topic_reply",
          title: @topic.title.truncate(60),
          author: @post.user.username,
          excerpt: @post.body.truncate(120),
          metadata: {
            topic_id: @topic.public_id,
            post_id: @post.id,
            path: "/app/forum/topics/#{@topic.public_id}#post-#{@post.id}"
          }
        )

        if NotificationLevelFilter.deliver_watch_email?(
          level: level,
          user: user,
          notification_type: "forum.topic_reply"
        ) && Community::WatchEmailDelivery.email_allowed?(user, notification_type: "forum.topic_reply")
          MailDeliveryJob.perform_later(
            "Community::ForumMailer",
            "topic_reply",
            "deliver_now",
            args: [ user.id, @topic.public_id, @post.id ]
          )
        end
      end

      ServiceResult.success
    end
  end
end

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
        in_app_enabled = NotificationLevelFilter.deliver_in_app?(
          level: level,
          user: user,
          topic: @topic,
          post: @post,
          context: :topic_reply
        ) && NotificationPreference.enabled?(
          user,
          channel: "in_app",
          notification_type: "forum.topic_reply"
        )
        email_enabled = NotificationLevelFilter.deliver_watch_email?(
          level: level,
          user: user,
          notification_type: "forum.topic_reply"
        )
        next unless in_app_enabled || email_enabled

        Community::ReadState.ensure_tracking!(user, @topic)

        if in_app_enabled
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
        end

        enqueue_email_after_commit(user) if email_enabled
      end

      ServiceResult.success
    end

    private

    def enqueue_email_after_commit(user)
      user_id = user.id
      topic_id = @topic.public_id
      post_id = @post.id
      ActiveRecord.after_all_transactions_commit do
        MailDeliveryJob.perform_later(
          "Community::ForumMailer",
          "topic_reply",
          "deliver_now",
          args: [ user_id, topic_id, post_id ]
        )
      end
    end
  end
end

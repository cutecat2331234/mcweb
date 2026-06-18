# frozen_string_literal: true

module Community
  class NotifyFollowedUserTopic < ApplicationService
    def initialize(topic:)
      @topic = topic
    end

    def call
      return ServiceResult.success if @topic.unlisted? || @topic.status != "published"

      followers = Community::UserFollow.where(followed: @topic.user).includes(:follower)
      recipient_ids = Community::FilterNotificationRecipients.call(
        actor_id: @topic.user_id,
        recipient_ids: followers.map(&:follower_id).uniq - [ @topic.user_id ],
        topic: @topic
      ).value

      Community::UserFollow.where(followed: @topic.user, follower_id: recipient_ids).includes(:follower).find_each do |follow|
        user = follow.follower

        next unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: "forum.followed_topic")

        Community::ReadState.ensure_tracking!(user, @topic)

        Notification.notify!(
          user: user,
          notification_type: "forum.followed_topic",
          title: "#{@topic.user.username} 发布了新主题",
          body: @topic.title,
          metadata: { path: "/app/forum/topics/#{@topic.public_id}", topic_id: @topic.public_id }
        )

        if Community::NotificationLevelFilter.deliver_watch_email?(
          level: "watching",
          user: user,
          notification_type: "forum.followed_topic"
        ) && Community::WatchEmailDelivery.email_allowed?(user, notification_type: "forum.followed_topic")
          MailDeliveryJob.perform_later(
            "Community::ForumMailer",
            "followed_topic",
            "deliver_now",
            args: [ user.id, @topic.public_id ]
          )
        end
      end

      ServiceResult.success
    end
  end
end

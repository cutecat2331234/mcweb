# frozen_string_literal: true

module Community
  class NotifyFollowedUserReply < ApplicationService
    def initialize(post:)
      @post = post
      @topic = post.topic
      @author = post.user
    end

    def call
      return ServiceResult.success(skipped: true) if @post.whisper?

      followers = Community::UserFollow.where(followed: @author).includes(:follower)
      recipient_ids = Community::FilterNotificationRecipients.call(
        actor_id: @author.id,
        recipient_ids: followers.map(&:follower_id).uniq - [ @author.id ]
      ).value

      Community::UserFollow.where(followed: @author, follower_id: recipient_ids).includes(:follower).find_each do |follow|
        user = follow.follower
        next unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: "forum.followed_reply")

        Notification.notify!(
          user: user,
          notification_type: "forum.followed_reply",
          title: "#{@author.username} 回复了主题",
          body: "#{@topic.title.truncate(60)} — #{@post.body.truncate(120)}",
          metadata: {
            topic_id: @topic.public_id,
            post_id: @post.id,
            username: @author.username,
            path: "/forum/topics/#{@topic.public_id}#post-#{@post.id}"
          }
        )

        if Community::NotificationLevelFilter.deliver_watch_email?(
          level: "watching",
          user: user,
          notification_type: "forum.followed_reply"
        ) && NotificationPreference.enabled?(user, channel: "email", notification_type: "forum.followed_reply")
          MailDeliveryJob.perform_later(
            "Community::ForumMailer",
            "followed_reply",
            "deliver_now",
            args: [ user.id, @topic.public_id, @post.id ]
          )
        end
      end

      ServiceResult.success
    end
  end
end

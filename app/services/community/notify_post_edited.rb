# frozen_string_literal: true

module Community
  class NotifyPostEdited < ApplicationService
    def initialize(post:)
      @post = post
      @topic = post.topic
    end

    def call
      subscriber_ids = Community::Subscription
        .where(subscribable: @topic)
        .where.not(user_id: @post.user_id)
        .pluck(:user_id)

      muted_ids = Community::TopicMute.where(forum_topic_id: @topic.id, user_id: subscriber_ids).pluck(:user_id)

      User.where(id: subscriber_ids - muted_ids).find_each do |user|
        next unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: "forum.post_edited")

        Notification.notify!(
          user: user,
          notification_type: "forum.post_edited",
          title: "帖子已编辑：#{@topic.title.truncate(60)}",
          body: "#{@post.user.username} 编辑了 ##{@post.floor_number}",
          metadata: {
            topic_id: @topic.public_id,
            post_id: @post.id,
            path: "/forum/topics/#{@topic.public_id}#post-#{@post.id}"
          }
        )
      end

      ServiceResult.success
    end
  end
end

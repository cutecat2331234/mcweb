# frozen_string_literal: true

module Community
  class NotifyFollowedUserTopic < ApplicationService
    def initialize(topic:)
      @topic = topic
    end

    def call
      followers = Community::UserFollow.where(followed: @topic.user).includes(:follower)
      followers.find_each do |follow|
        user = follow.follower
        next if user.id == @topic.user_id

        next unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: "forum.followed_topic")

        Notification.notify!(
          user: user,
          notification_type: "forum.followed_topic",
          title: "#{@topic.user.username} 发布了新主题",
          body: @topic.title,
          metadata: { path: "/forum/topics/#{@topic.public_id}", topic_id: @topic.public_id }
        )
      end

      ServiceResult.success
    end
  end
end

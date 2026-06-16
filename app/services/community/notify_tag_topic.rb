# frozen_string_literal: true

module Community
  class NotifyTagTopic < ApplicationService
    def initialize(topic:, tags:)
      @topic = topic
      @tags = Array(tags)
    end

    def call
      return ServiceResult.success if @tags.empty?
      return ServiceResult.success if @topic.unlisted? || @topic.status != "published"

      subscriber_ids = Community::Subscription
        .where(subscribable: @tags)
        .where.not(user_id: @topic.user_id)
        .pluck(:user_id, :notification_level)
        .uniq { |user_id, _| user_id }

      recipient_ids = Community::FilterNotificationRecipients.call(
        actor_id: @topic.user_id,
        recipient_ids: subscriber_ids.map(&:first),
        topic: @topic
      ).value

      levels_by_user = subscriber_ids.to_h

      User.where(id: recipient_ids).find_each do |user|
        next unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: "forum.tag_topic")

        tag_names = @tags.map(&:name).join(", ")
        Notification.notify!(
          user: user,
          notification_type: "forum.tag_topic",
          title: "关注标签有新主题：#{@topic.title.truncate(60)}",
          body: "#{@topic.user.username} 使用了标签 #{tag_names}",
          metadata: {
            topic_id: @topic.public_id,
            path: "/app/forum/topics/#{@topic.public_id}"
          }
        )
      end

      ServiceResult.success
    end
  end
end

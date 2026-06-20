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
        level = levels_by_user[user.id] || "watching"
        next unless NotificationLevelFilter.deliver_in_app?(level: level, user: user, context: :tag_topic)
        next unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: "forum.tag_topic")

        Community::ReadState.ensure_tracking!(user, @topic)

        tag_names = @tags.map(&:name).join(", ")
        Community::InAppNotification.notify(
          user: user,
          notification_type: "forum.tag_topic",
          key: "tag_topic",
          title: @topic.title.truncate(60),
          author: @topic.user.username,
          tags: tag_names,
          metadata: {
            topic_id: @topic.public_id,
            path: "/app/forum/topics/#{@topic.public_id}"
          }
        )

        level = levels_by_user[user.id] || "watching"
        if NotificationLevelFilter.deliver_watch_email?(
          level: level,
          user: user,
          notification_type: "forum.tag_topic"
        ) && Community::WatchEmailDelivery.email_allowed?(user, notification_type: "forum.tag_topic")
          MailDeliveryJob.perform_later(
            "Community::ForumMailer",
            "tag_topic",
            "deliver_now",
            args: [ user.id, @topic.public_id, tag_names ]
          )
        end
      end

      ServiceResult.success
    end
  end
end

# frozen_string_literal: true

module Community
  class NotifySectionTopic < ApplicationService
    def initialize(topic:)
      @topic = topic
      @section = topic.section
    end

    def call
      subscriber_ids = Community::Subscription
        .where(subscribable: @section)
        .where.not(user_id: @topic.user_id)
        .pluck(:user_id, :notification_level)

      muted_ids = Community::SectionMute.where(forum_section_id: @section.id, user_id: subscriber_ids.map(&:first)).pluck(:user_id)
      levels_by_user = subscriber_ids.to_h

      User.where(id: subscriber_ids.map(&:first) - muted_ids).find_each do |user|
        level = levels_by_user[user.id] || "watching"
        next unless NotificationLevelFilter.deliver_in_app?(level: level, user: user, context: :section_topic)
        next unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: "forum.section_topic")

        Notification.notify!(
          user: user,
          notification_type: "forum.section_topic",
          title: "分区有新主题：#{@topic.title.truncate(60)}",
          body: "#{@topic.user.username} 在 #{@section.name} 发布了新主题",
          metadata: {
            topic_id: @topic.public_id,
            section_slug: @section.slug,
            path: "/forum/topics/#{@topic.public_id}"
          }
        )

        level = levels_by_user[user.id] || "watching"
        if NotificationLevelFilter.deliver_watch_email?(
          level: level,
          user: user,
          notification_type: "forum.section_topic"
        ) && Community::WatchEmailDelivery.email_allowed?(user, notification_type: "forum.section_topic")
          MailDeliveryJob.perform_later(
            "Community::ForumMailer",
            "section_topic",
            "deliver_now",
            args: [ user.id, @topic.public_id ]
          )
        end
      end

      ServiceResult.success
    end
  end
end

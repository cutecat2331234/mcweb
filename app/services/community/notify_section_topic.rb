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
        .pluck(:user_id)

      User.where(id: subscriber_ids).find_each do |user|
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

        if NotificationPreference.enabled?(user, channel: "email", notification_type: "forum.section_topic")
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

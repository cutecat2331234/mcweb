# frozen_string_literal: true

module Community
  class NotifyTopicAssigned < ApplicationService
    def initialize(topic:, assignee:, actor:)
      @topic = topic
      @assignee = assignee
      @actor = actor
    end

    def call
      return ServiceResult.success(skipped: true) if @assignee.id == @actor.id

      email_enabled = Community::InstantEmailDelivery.allowed?(@assignee, notification_type: "forum.topic_assigned")
      in_app_enabled = NotificationPreference.enabled?(@assignee, channel: "in_app", notification_type: "forum.topic_assigned")
      return ServiceResult.success(skipped: true) unless email_enabled || in_app_enabled

      if in_app_enabled
        Community::InAppNotification.notify(
          user: @assignee,
          notification_type: "forum.topic_assigned",
          key: "topic_assigned",
          actor: @actor.username,
          title: @topic.title,
          metadata: {
            topic_id: @topic.public_id,
            path: "#{Mcweb::Paths::APP_PREFIX}/forum/topics/#{@topic.public_id}"
          }
        )
      end

      if email_enabled
        MailDeliveryJob.perform_later(
          "Community::ForumMailer",
          "topic_assigned",
          "deliver_now",
          args: [ @assignee.id, @topic.public_id, @actor.id ]
        )
      end

      ServiceResult.success
    end
  end
end

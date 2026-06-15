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
      return ServiceResult.success(skipped: true) unless NotificationPreference.enabled?(@assignee, channel: "in_app", notification_type: "forum.topic_assigned")

      Notification.notify!(
        user: @assignee,
        notification_type: "forum.topic_assigned",
        title: "你被指派了一个主题",
        body: "#{@actor.username} 将「#{@topic.title}」指派给你。",
        metadata: {
          topic_id: @topic.public_id,
          path: "/forum/topics/#{@topic.public_id}"
        }
      )

      ServiceResult.success
    end
  end
end

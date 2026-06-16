# frozen_string_literal: true

module Community
  class NotifyTopicInvite < ApplicationService
    def initialize(invite:)
      @invite = invite
      @topic = invite.topic
      @user = invite.user
      @inviter = invite.invited_by
    end

    def call
      return ServiceResult.success unless NotificationPreference.enabled?(@user, channel: "in_app", notification_type: "forum.topic_invite")

      Notification.notify!(
        user: @user,
        notification_type: "forum.topic_invite",
        title: "#{@inviter.username} 邀请你关注主题",
        body: @topic.title,
        metadata: { path: "/app/forum/topics/#{@topic.public_id}", topic_id: @topic.public_id }
      )

      ServiceResult.success
    end
  end
end

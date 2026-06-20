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
      email_enabled = Community::InstantEmailDelivery.allowed?(@user, notification_type: "forum.topic_invite")
      in_app_enabled = NotificationPreference.enabled?(@user, channel: "in_app", notification_type: "forum.topic_invite")
      return ServiceResult.success unless email_enabled || in_app_enabled

      if in_app_enabled
        Community::InAppNotification.notify(
          user: @user,
          notification_type: "forum.topic_invite",
          key: "topic_invite",
          inviter: @inviter.username,
          title: @topic.title,
          metadata: { path: "#{Mcweb::Paths::APP_PREFIX}/forum/topics/#{@topic.public_id}", topic_id: @topic.public_id }
        )
      end

      if email_enabled
        MailDeliveryJob.perform_later(
          "Community::ForumMailer",
          "topic_invite",
          "deliver_now",
          args: [ @user.id, @topic.public_id, @inviter.id ]
        )
      end

      ServiceResult.success
    end
  end
end

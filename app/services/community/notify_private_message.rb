# frozen_string_literal: true

module Community
  class NotifyPrivateMessage < ApplicationService
    def initialize(message:, conversation:)
      @message = message
      @conversation = conversation
    end

    def call
      @conversation.participants.where.not(user_id: @message.user_id).find_each do |participant|
        user = participant.user
        next unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: "forum.private_message")

        Notification.notify!(
          user: user,
          notification_type: "forum.private_message",
          title: @conversation.is_group? ? "群组「#{@conversation.title}」新消息" : "来自 #{@message.user.username} 的私信",
          body: @message.body.truncate(120),
          metadata: { url: "/forum/conversations/#{@conversation.id}" }
        )

        if NotificationPreference.enabled?(user, channel: "email", notification_type: "forum.private_message")
          MailDeliveryJob.perform_later(
            "Community::ForumMailer",
            "private_message",
            "deliver_now",
            args: [ user.id, @conversation.id, @message.id ]
          )
        end
      end

      ServiceResult.success
    end
  end
end

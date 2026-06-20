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
        next if participant.muted_at.present?
        next unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: "forum.private_message")

        title_key = @conversation.is_group? ? "private_message.title_group" : "private_message.title_direct"
        Community::InAppNotification.notify(
          user: user,
          notification_type: "forum.private_message",
          key: "private_message",
          title_key: title_key,
          title: @conversation.title,
          sender: @message.user.username,
          excerpt: @message.body.truncate(120),
          metadata: {
            conversation_id: @conversation.id,
            url: "/app/forum/conversations/#{@conversation.id}",
            path: "/app/forum/conversations/#{@conversation.id}"
          }
        )

        if Community::InstantEmailDelivery.allowed?(user, notification_type: "forum.private_message")
          next if participant.muted_at.present?

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

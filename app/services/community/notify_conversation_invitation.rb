# frozen_string_literal: true

module Community
  class NotifyConversationInvitation < ApplicationService
    def initialize(invitation:)
      @invitation = invitation
    end

    def call
      return ServiceResult.success unless @invitation&.id

      mail_args = nil
      Community::ConversationInvitation.transaction do
        invitation = Community::ConversationInvitation.lock.find_by(id: @invitation.id)
        return ServiceResult.success unless invitation
        return ServiceResult.success unless Community::NotificationAccess.conversation_invitation_visible?(
          user: invitation.user,
          invitation: invitation
        )

        user = invitation.user
        conversation = invitation.conversation
        inviter = invitation.invited_by
        path = Rails.application.routes.url_helpers.forum_conversations_path(
          anchor: "conversation-invitations"
        )

        if NotificationPreference.enabled?(user, channel: "in_app", notification_type: "forum.conversation_invite")
          Community::InAppNotification.notify(
            user: user,
            notification_type: "forum.conversation_invite",
            key: "conversation_invite",
            inviter: inviter.username,
            title: conversation.title,
            metadata: {
              path: path,
              conversation_id: conversation.id,
              conversation_invitation_public_id: invitation.public_id
            }
          )
        end

        if Community::InstantEmailDelivery.allowed?(user, notification_type: "forum.conversation_invite")
          mail_args = [ user.id, invitation.public_id ]
        end
      end

      if mail_args
        MailDeliveryJob.perform_later(
          "Community::ForumMailer",
          "conversation_invitation",
          "deliver_now",
          args: mail_args
        )
      end

      ServiceResult.success
    end
  end
end

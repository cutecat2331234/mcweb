# frozen_string_literal: true

module Community
  class DeclineConversationInvitation < ApplicationService
    def initialize(user:, invitation:)
      @user = user
      @invitation = invitation
    end

    def call
      return ServiceResult.failure(error: :conversation_invitation_not_found) unless @invitation.user_id == @user.id

      Community::ConversationInvitation.transaction do
        invitation = Community::ConversationInvitation.lock.find(@invitation.id)
        return ServiceResult.success(invitation) if invitation.declined?
        return ServiceResult.failure(error: :conversation_invitation_not_pending) unless invitation.pending?

        now = Time.current
        if invitation.expires_at <= now
          invitation.update!(status: "expired", resolved_at: now)
          mark_notification_read(invitation, at: now)
          return ServiceResult.failure(error: :conversation_invitation_expired)
        end

        if invitation.blocked_by_participant?
          invitation.update!(status: "revoked", resolved_at: now)
          mark_notification_read(invitation, at: now)
          return ServiceResult.failure(error: :conversation_invitation_blocked)
        end

        invitation.update!(status: "declined", resolved_at: now)
        mark_notification_read(invitation, at: now)
        ServiceResult.success(invitation)
      end
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    end

    private

    def mark_notification_read(invitation, at:)
      Community::MarkConversationInvitationNotificationsRead.call(
        user_id: invitation.user_id,
        invitation_public_id: invitation.public_id,
        at: at
      )
    end
  end
end

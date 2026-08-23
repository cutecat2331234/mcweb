# frozen_string_literal: true

module Community
  class AcceptConversationInvitation < ApplicationService
    def initialize(user:, invitation:)
      @user = user
      @invitation = invitation
    end

    def call
      return ServiceResult.failure(error: :conversation_invitation_not_found) unless @invitation.user_id == @user.id

      result = Community::ConversationMembershipLock.with(
        conversation: @invitation.conversation,
        users: [ @user, @invitation.invited_by ]
      ) do
        accept_locked
      end
      result || ServiceResult.failure(error: :conversation_invitation_conflict, code: "conflict")
    rescue Community::ConversationMembershipLock::ParticipantSetChanged,
           ActiveRecord::RecordNotUnique,
           ActiveRecord::StaleObjectError
      ServiceResult.failure(error: :conversation_invitation_conflict, code: "conflict")
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    end

    private

    def accept_locked
      invitation = Community::ConversationInvitation.lock.find(@invitation.id)
      conversation = invitation.conversation

      if invitation.accepted?
        return ServiceResult.success(conversation) if conversation.participant?(@user)

        return ServiceResult.failure(error: :conversation_invitation_conflict, code: "conflict")
      end
      return ServiceResult.failure(error: :conversation_invitation_not_pending) unless invitation.pending?

      now = Time.current
      if invitation.expires_at <= now
        invitation.update!(status: "expired", resolved_at: now)
        mark_notification_read(invitation, at: now)
        return ServiceResult.failure(error: :conversation_invitation_expired)
      end

      eligibility = Community::ConversationInvitationEligibility.call(
        actor: invitation.invited_by,
        conversation: conversation,
        invitee: @user,
        require_participant_actor: false,
        enforce_recipient_policy: false
      )
      if eligibility.failure?
        if invitation.blocked_by_participant?
          invitation.update!(status: "revoked", resolved_at: now)
          mark_notification_read(invitation, at: now)
          return ServiceResult.failure(error: :conversation_invitation_blocked)
        end
        return eligibility
      end

      if conversation.participants.count >= Community::AddConversationParticipant.max_participants
        return ServiceResult.failure(error: :group_full)
      end

      conversation.participants.create!(user: @user)
      invitation.update!(status: "accepted", resolved_at: now)
      mark_notification_read(invitation, at: now)
      ServiceResult.success(conversation)
    end

    def mark_notification_read(invitation, at:)
      Community::MarkConversationInvitationNotificationsRead.call(
        user_id: invitation.user_id,
        invitation_public_id: invitation.public_id,
        at: at
      )
    end
  end
end

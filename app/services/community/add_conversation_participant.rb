# frozen_string_literal: true

module Community
  class AddConversationParticipant < ApplicationService
    MAX_PARTICIPANTS = 10

    def self.max_participants
      [ SiteSetting.get("forum.group_pm_max_participants", MAX_PARTICIPANTS.to_s).to_i, 1 ].max
    end

    def initialize(actor:, conversation:, username:, direct_membership: false, system_operation: false)
      @actor = actor
      @conversation = conversation
      @username = username.to_s.strip
      @direct_membership = direct_membership
      @system_operation = system_operation
    end

    def call
      return ServiceResult.failure(error: :not_group_conversation) unless @conversation.is_group?
      if @direct_membership && !direct_membership_authorized?
        return ServiceResult.failure(error: :direct_conversation_membership_unauthorized)
      end

      user = User.find_by(username: @username)
      return ServiceResult.failure(error: :user_not_found) unless user

      invitation_to_notify = nil
      direct_user_to_notify = nil
      result = Community::ConversationMembershipLock.with(
        conversation: @conversation,
        users: [ @actor, user ].compact
      ) do
        eligibility = Community::ConversationInvitationEligibility.call(
          actor: @actor,
          conversation: @conversation,
          invitee: user,
          require_participant_actor: !@direct_membership,
          enforce_recipient_policy: !@system_operation
        )
        next eligibility if eligibility.failure?

        if @direct_membership
          now = Time.current
          pending_invitation = @conversation.invitations.where(user: user, status: "pending").lock.first
          if pending_invitation && !pending_invitation.actionable?(at: now)
            pending_invitation.update!(status: "expired", resolved_at: now)
            mark_invitation_notification_read!(pending_invitation, at: now)
            pending_invitation = nil
          end

          reserved_target_slot = pending_invitation ? 1 : 0
          if @conversation.occupied_participant_slots - reserved_target_slot >= self.class.max_participants
            next ServiceResult.failure(error: :group_full)
          end

          @conversation.participants.create!(user: user)
          if pending_invitation
            pending_invitation.update!(status: "accepted", resolved_at: now)
            mark_invitation_notification_read!(pending_invitation, at: now)
          end
          direct_user_to_notify = user
          next ServiceResult.success(@conversation)
        end

        now = Time.current
        existing = @conversation.invitations.where(user: user, status: "pending").lock.first
        if existing&.actionable?(at: now)
          next ServiceResult.success(@conversation)
        elsif existing
          existing.update!(status: "expired", resolved_at: now)
          mark_invitation_notification_read!(existing, at: now)
        end

        if @conversation.occupied_participant_slots >= self.class.max_participants
          next ServiceResult.failure(error: :group_full)
        end

        invitation_to_notify = @conversation.invitations.create!(
          user: user,
          invited_by: @actor,
          expires_at: now + Community::ConversationInvitation::DEFAULT_EXPIRY
        )
        ServiceResult.success(@conversation)
      end

      if result&.success?
        Community::NotifyConversationInvitation.call(invitation: invitation_to_notify) if invitation_to_notify
        notify_direct_add!(direct_user_to_notify) if direct_user_to_notify
      end
      result || ServiceResult.failure(error: :conversation_invitation_conflict, code: "conflict")
    rescue Community::ConversationMembershipLock::ParticipantSetChanged,
           ActiveRecord::RecordNotUnique,
           ActiveRecord::StaleObjectError
      ServiceResult.failure(error: :conversation_invitation_conflict, code: "conflict")
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    end

    def self.can_add_member?(actor, conversation)
      return true unless conversation.is_group?

      creator_only = conversation.invites_locked? ||
        SiteSetting.get("forum.group_pm_creator_only_add", "false") == "true"
      return true unless creator_only

      staff = actor&.permission?("forum.topics.lock")
      staff || actor&.id == conversation.creator_id
    end

    private

    def direct_membership_authorized?
      (@system_operation && @actor.nil?) || @actor&.permission?("forum.topics.lock")
    end

    def mark_invitation_notification_read!(invitation, at:)
      Community::MarkConversationInvitationNotificationsRead.call(
        user_id: invitation.user_id,
        invitation_public_id: invitation.public_id,
        at: at
      )
    end

    def notify_direct_add!(user)
      return unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: "forum.conversation_invite")

      Community::InAppNotification.notify(
        user: user,
        notification_type: "forum.conversation_invite",
        key: "added_to_conversation",
        adder: @actor&.username || I18n.t("mcweb.forum.system_actor"),
        metadata: {
          path: Rails.application.routes.url_helpers.forum_conversation_path(@conversation),
          conversation_id: @conversation.id
        }
      )
    end
  end
end

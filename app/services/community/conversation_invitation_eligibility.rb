# frozen_string_literal: true

module Community
  class ConversationInvitationEligibility < ApplicationService
    def initialize(actor:, conversation:, invitee:, require_participant_actor: true, enforce_recipient_policy: true)
      @actor = actor
      @conversation = conversation
      @invitee = invitee
      @require_participant_actor = require_participant_actor
      @enforce_recipient_policy = enforce_recipient_policy
    end

    def call
      return ServiceResult.failure(error: :not_group_conversation) unless @conversation.is_group?
      if @require_participant_actor
        return ServiceResult.failure(error: :only_participants_can_add) unless @actor && @conversation.participant?(@actor)
        return ServiceResult.failure(error: :only_creator_can_add) unless Community::AddConversationParticipant.can_add_member?(@actor, @conversation)
      end
      return ServiceResult.failure(error: :user_already_participant) if @conversation.participant?(@invitee)
      return ServiceResult.failure(error: :cannot_add_self) if @actor && @invitee.id == @actor.id
      return ServiceResult.failure(error: :cannot_message_blocked_user) if blocked_by_any_participant?
      return ServiceResult.failure(error: :user_cannot_pm) unless @invitee.session_eligible?
      return ServiceResult.failure(error: :user_silenced) if Community::UserSilence.silenced?(@invitee)
      return ServiceResult.failure(error: :user_cannot_pm) unless Community::TrustLevel.can_send_pm?(@invitee)
      if @enforce_recipient_policy && @actor && !Community::PmPolicy.accepts?(recipient: @invitee, sender: @actor)
        return ServiceResult.failure(error: "pm_not_accepted")
      end

      pm_restriction = Community::CheckWarningRestrictions.call(user: @invitee, action: :pm)
      return pm_restriction if pm_restriction.failure?

      ServiceResult.success
    end

    private

    def blocked_by_any_participant?
      blocked_ids = Community::UserBlock.blocked_user_ids(@invitee)
      blocked_ids.any? && @conversation.participants.where(user_id: blocked_ids).exists?
    end
  end
end

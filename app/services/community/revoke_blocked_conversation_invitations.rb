# frozen_string_literal: true

module Community
  class RevokeBlockedConversationInvitations < ApplicationService
    def initialize(first_user:, second_user:, at: Time.current)
      @first_user = first_user
      @second_user = second_user
      @at = at
    end

    def call
      pending = Community::ConversationInvitation.where(status: "pending")
      first_groups = Community::ConversationParticipant
        .where(user: @first_user)
        .select(:forum_conversation_id)
      second_groups = Community::ConversationParticipant
        .where(user: @second_user)
        .select(:forum_conversation_id)

      first_invited_by_second = pending.where(user: @first_user, invited_by: @second_user)
      first_invited_into_second_group = pending.where(user: @first_user, forum_conversation_id: second_groups)
      second_invited_by_first = pending.where(user: @second_user, invited_by: @first_user)
      second_invited_into_first_group = pending.where(user: @second_user, forum_conversation_id: first_groups)
      affected = first_invited_by_second
        .or(first_invited_into_second_group)
        .or(second_invited_by_first)
        .or(second_invited_into_first_group)

      affected_notifications = affected.pluck(:user_id, :public_id)
      count = affected.update_all(status: "revoked", resolved_at: @at, updated_at: @at)
      affected_notifications.each do |user_id, public_id|
        Community::MarkConversationInvitationNotificationsRead.call(
          user_id: user_id,
          invitation_public_id: public_id,
          at: @at
        )
      end
      ServiceResult.success(revoked: count)
    end
  end
end

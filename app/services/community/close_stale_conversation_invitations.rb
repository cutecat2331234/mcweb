# frozen_string_literal: true

module Community
  class CloseStaleConversationInvitations < ApplicationService
    def initialize(user: nil, at: Time.current)
      @user = user
      @at = at
    end

    def call
      scope = Community::ConversationInvitation.where(status: "pending")
      scope = scope.where(user: @user) if @user
      expired_scope = scope.where(expires_at: ..@at)
      expired_notifications = expired_scope.pluck(:user_id, :public_id)
      expired_count = expired_scope.update_all(
        status: "expired",
        resolved_at: @at,
        updated_at: @at
      )
      mark_notifications_read(expired_notifications)

      revoked_count = 0
      scope.where("expires_at > ?", @at).includes(:user, conversation: :participants).find_each do |invitation|
        next unless invitation.blocked_by_participant?

        changed = Community::ConversationInvitation
          .where(id: invitation.id, status: "pending")
          .update_all(status: "revoked", resolved_at: @at, updated_at: @at)
        revoked_count += changed
        mark_notifications_read([ [ invitation.user_id, invitation.public_id ] ]) if changed.positive?
      end

      ServiceResult.success(expired: expired_count, revoked: revoked_count)
    end

    private

    def mark_notifications_read(rows)
      rows.each do |user_id, public_id|
        Community::MarkConversationInvitationNotificationsRead.call(
          user_id: user_id,
          invitation_public_id: public_id,
          at: @at
        )
      end
    end
  end
end

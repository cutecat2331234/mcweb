# frozen_string_literal: true

module Community
  class MarkConversationInvitationNotificationsRead < ApplicationService
    def initialize(user_id:, invitation_public_id:, at: Time.current)
      @user_id = user_id
      @invitation_public_id = invitation_public_id.to_s
      @at = at
    end

    def call
      ids = Notification
        .where(user_id: @user_id, notification_type: "forum.conversation_invite", read_at: nil)
        .select(:id, :metadata)
        .filter_map do |notification|
          values = notification.metadata.is_a?(Hash) ? notification.metadata : {}
          value = values["conversation_invitation_public_id"] || values[:conversation_invitation_public_id]
          notification.id if value.to_s == @invitation_public_id
        end
      Notification.where(id: ids, read_at: nil).update_all(read_at: @at, updated_at: @at) if ids.any?

      ServiceResult.success(marked_read: ids.length)
    end
  end
end

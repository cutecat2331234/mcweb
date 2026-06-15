# frozen_string_literal: true

module Community
  class ToggleConversationMute < ApplicationService
    def initialize(user:, conversation:)
      @user = user
      @conversation = conversation
    end

    def call
      participant = @conversation.participants.find_by(user: @user)
      return ServiceResult.failure(error: "你不是此会话的参与者") unless participant

      if participant.muted_at.present?
        participant.update!(muted_at: nil)
        ServiceResult.success(muted: false)
      else
        participant.update!(muted_at: Time.current)
        ServiceResult.success(muted: true)
      end
    end
  end
end

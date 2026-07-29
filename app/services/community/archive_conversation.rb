# frozen_string_literal: true

module Community
  class ArchiveConversation < ApplicationService
    def initialize(user:, conversation:)
      @user = user
      @conversation = conversation
    end

    def call
      participant = @conversation.participants.find_by(user: @user)
      return ServiceResult.failure(error: :not_a_participant) unless participant

      participant.update!(archived_at: Time.current)
      ServiceResult.success(archived: true)
    end
  end
end

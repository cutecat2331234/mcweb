# frozen_string_literal: true

module Community
  class ToggleConversationMute < ApplicationService
    def initialize(user:, conversation:, muted: nil)
      @user = user
      @conversation = conversation
      @muted = muted
    end

    def call
      participant = @conversation.participants.find_by(user: @user)
      return ServiceResult.failure(error: "not_a_participant") unless participant

      currently_muted = participant.muted_at.present?
      # Explicit target when given (idempotent mute/unmute endpoints); fall back to
      # toggling when no target is supplied.
      desired = @muted.nil? ? !currently_muted : ActiveModel::Type::Boolean.new.cast(@muted)

      participant.update!(muted_at: desired ? Time.current : nil) if desired != currently_muted
      ServiceResult.success(muted: desired)
    end
  end
end

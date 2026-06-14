# frozen_string_literal: true

module Community
  class RemoveConversationParticipant < ApplicationService
    def initialize(actor:, conversation:, username:)
      @actor = actor
      @conversation = conversation
      @username = username.to_s.strip
    end

    def call
      return ServiceResult.failure(error: "Not a group conversation.") unless @conversation.is_group?

      user = User.find_by(username: @username)
      return ServiceResult.failure(error: "User not found.") unless user

      participant = @conversation.participants.find_by(user: user)
      return ServiceResult.failure(error: "User is not a participant.") unless participant

      unless @actor.id == user.id || @actor.id == @conversation.creator_id || @actor.permission?("forum.topics.lock")
        return ServiceResult.failure(error: "Not allowed.")
      end

      return ServiceResult.failure(error: "Cannot remove the last participant.") if @conversation.participants.count <= 1

      Community::Conversation.transaction do
        participant.destroy!
        transfer_creator_if_needed!(removed_user: user)
      end

      ServiceResult.success(@conversation.reload)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def transfer_creator_if_needed!(removed_user:)
      return unless @conversation.creator_id == removed_user.id

      next_creator = @conversation.participants.order(:created_at).first&.user
      @conversation.update!(creator_id: next_creator&.id)
    end
  end
end

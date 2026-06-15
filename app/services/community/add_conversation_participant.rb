# frozen_string_literal: true

module Community
  class AddConversationParticipant < ApplicationService
    MAX_PARTICIPANTS = 10

    def initialize(actor:, conversation:, username:)
      @actor = actor
      @conversation = conversation
      @username = username.to_s.strip
    end

    def call
      return ServiceResult.failure(error: "Not a group conversation.") unless @conversation.is_group?
      return ServiceResult.failure(error: "Only participants can add members.") unless @conversation.participant?(@actor)
      return ServiceResult.failure(error: "Group is full.") if @conversation.participants.count >= MAX_PARTICIPANTS

      user = User.find_by(username: @username)
      return ServiceResult.failure(error: "User not found.") unless user
      return ServiceResult.failure(error: "User is already a participant.") if @conversation.participant?(user)
      return ServiceResult.failure(error: "Cannot add yourself.") if user.id == @actor.id
      return ServiceResult.failure(error: "Cannot message blocked user.") if Community::UserBlock.blocked?(@actor, user)
      return ServiceResult.failure(error: "User is silenced.") if Community::UserSilence.silenced?(user)
      return ServiceResult.failure(error: "User cannot participate in private messages.") unless Community::TrustLevel.can_send_pm?(user)

      pm_restriction = Community::CheckWarningRestrictions.call(user: user, action: :pm)
      return pm_restriction if pm_restriction.failure?

      @conversation.participants.create!(user: user)
      ServiceResult.success(@conversation)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

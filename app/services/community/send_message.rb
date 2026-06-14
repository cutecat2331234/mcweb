# frozen_string_literal: true

module Community
  class SendMessage < ApplicationService
    def initialize(user:, conversation:, body:)
      @user = user
      @conversation = conversation
      @body = body.to_s.strip
    end

    def call
      return ServiceResult.failure(error: "Not a participant.") unless participant?
      return ServiceResult.failure(error: "Message is too short.") if @body.length < 1
      return ServiceResult.failure(error: "New members cannot send private messages yet.") unless Community::TrustLevel.can_send_pm?(@user)

      others = @conversation.participants.where.not(user: @user).includes(:user).map(&:user)
      others.each do |other|
        if Community::UserBlock.blocked?(@user, other)
          return ServiceResult.failure(error: "You cannot message #{other.username}.")
        end
      end

      message = @conversation.messages.create!(user: @user, body: @body)
      @conversation.update!(last_message_at: message.created_at)
      @conversation.mark_read_for!(@user)

      Community::NotifyPrivateMessage.call(message: message, conversation: @conversation)

      ServiceResult.success(message)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def participant?
      @conversation.participants.exists?(user: @user)
    end
  end
end

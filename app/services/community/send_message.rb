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

      other = @conversation.participants.where.not(user: @user).includes(:user).map(&:user).first
      if other && Community::UserBlock.blocked?(@user, other)
        return ServiceResult.failure(error: "You cannot message this user.")
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

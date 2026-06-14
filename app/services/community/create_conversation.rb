# frozen_string_literal: true

module Community
  class CreateConversation < ApplicationService
    def initialize(sender:, recipient_username:, body:)
      @sender = sender
      @recipient = User.find_by(username: recipient_username.to_s.strip)
      @body = body.to_s.strip
    end

    def call
      return ServiceResult.failure(error: "Recipient not found.") unless @recipient
      return ServiceResult.failure(error: "You cannot message yourself.") if @sender.id == @recipient.id
      return ServiceResult.failure(error: "You cannot message this user.") if Community::UserBlock.blocked?(@sender, @recipient)
      return ServiceResult.failure(error: "Message is too short.") if @body.length < 1

      conversation = find_existing || create_conversation!
      message = conversation.messages.create!(user: @sender, body: @body)
      conversation.update!(last_message_at: message.created_at)

      Community::NotifyPrivateMessage.call(message: message, conversation: conversation)

      ServiceResult.success(conversation: conversation, message: message)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def find_existing
      my_ids = Community::ConversationParticipant.where(user: @sender).pluck(:forum_conversation_id)
      recipient_participant = Community::ConversationParticipant.find_by(
        forum_conversation_id: my_ids,
        user_id: @recipient.id
      )
      recipient_participant&.conversation
    end

    def create_conversation!
      Community::Conversation.create!.tap do |conversation|
        conversation.participants.create!(user: @sender)
        conversation.participants.create!(user: @recipient)
      end
    end
  end
end

# frozen_string_literal: true

module Community
  class CreateGroupConversation < ApplicationService
    MAX_PARTICIPANTS = 10

    def initialize(sender:, title:, recipient_usernames:, body:)
      @sender = sender
      @title = title.to_s.strip
      @usernames = Array(recipient_usernames).flat_map { |n| n.to_s.split(",") }.map(&:strip).reject(&:blank?).uniq
      @body = body.to_s.strip
    end

    def call
      return ServiceResult.failure(error: "Group title is required.") if @title.blank?
      return ServiceResult.failure(error: "Add at least one other participant.") if @usernames.empty?
      return ServiceResult.failure(error: "Too many participants.") if @usernames.size > MAX_PARTICIPANTS
      return ServiceResult.failure(error: "Message is too short.") if @body.length < 1

      recipients = User.where(username: @usernames)
      missing = @usernames - recipients.pluck(:username)
      return ServiceResult.failure(error: "Users not found: #{missing.join(', ')}") if missing.any?

      recipients.each do |recipient|
        if Community::UserBlock.blocked?(@sender, recipient)
          return ServiceResult.failure(error: "You cannot message #{recipient.username}.")
        end
      end

      conversation = nil
      Community::Conversation.transaction do
        conversation = Community::Conversation.create!(
          title: @title,
          is_group: true,
          creator: @sender,
          last_message_at: Time.current
        )
        conversation.participants.create!(user: @sender)
        recipients.each { |user| conversation.participants.create!(user: user) }
        message = conversation.messages.create!(user: @sender, body: @body)
        conversation.update!(last_message_at: message.created_at)
      end

      message = conversation.messages.order(:created_at).last
      Community::NotifyPrivateMessage.call(message: message, conversation: conversation)

      ServiceResult.success(conversation: conversation, message: message)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

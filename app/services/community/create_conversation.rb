# frozen_string_literal: true

module Community
  class CreateConversation < ApplicationService
    def initialize(sender:, recipient_username:, body:, attachment_ids: [], ip_address: nil)
      @sender = sender
      @recipient = User.find_by(username: recipient_username.to_s.strip)
      @body = body.to_s.strip
      @attachment_ids = attachment_ids
      @ip_address = ip_address
    end

    def call
      rate_limit_result = Administration::AbuseRateLimit.call(
        action: :private_message,
        account: @sender,
        ip_address: @ip_address
      )
      return rate_limit_result if rate_limit_result.failure?

      return ServiceResult.failure(error: :recipient_not_found) unless @recipient
      return ServiceResult.failure(error: :cannot_message_self) if @sender.id == @recipient.id
      return ServiceResult.failure(error: :cannot_message_user) if Community::UserBlock.blocked?(@sender, @recipient)
      return ServiceResult.failure(error: "pm_not_accepted") unless Community::PmPolicy.accepts?(recipient: @recipient, sender: @sender)
      return ServiceResult.failure(error: :new_members_cannot_send_pm) unless Community::TrustLevel.can_send_pm?(@sender)

      pm_restriction = Community::CheckWarningRestrictions.call(user: @sender, action: :pm)
      return pm_restriction if pm_restriction.failure?

      if Community::TrustLevel.contains_link?(@body) && !Community::TrustLevel.can_post_links?(@sender)
        return ServiceResult.failure(error: :new_members_cannot_post_links)
      end

      link_restriction = Community::CheckWarningRestrictions.call(user: @sender, action: :link)
      return link_restriction if link_restriction.failure? && Community::TrustLevel.contains_link?(@body)

      return ServiceResult.failure(error: :message_too_short) if @body.length < 1

      conversation = nil
      message = nil
      attachment_result = nil
      Community::Conversation.transaction do
        conversation = find_existing || create_conversation!
        message = conversation.messages.create!(user: @sender, body: @body)
        attachment_result = Community::LinkMessageAttachments.call(
          user: @sender,
          message: message,
          attachment_ids: @attachment_ids
        )
        raise ActiveRecord::Rollback if attachment_result.failure?

        conversation.update!(last_message_at: message.created_at)
        conversation.mark_read_for!(@sender)
        conversation.unarchive_all_participants!
      end
      return attachment_result if attachment_result&.failure?
      return ServiceResult.failure(error: "message_create_failed") unless message&.persisted?

      Community::NotifyPrivateMessage.call(message: message, conversation: conversation)

      ServiceResult.success(conversation: conversation, message: message)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def find_existing
      my_ids = Community::ConversationParticipant.where(user: @sender).pluck(:forum_conversation_id)
      Community::Conversation.where(id: my_ids, is_group: false)
        .joins(:participants)
        .where(forum_conversation_participants: { user_id: @recipient.id })
        .first
    end

    def create_conversation!
      Community::Conversation.create!.tap do |conversation|
        conversation.participants.create!(user: @sender)
        conversation.participants.create!(user: @recipient)
      end
    end
  end
end

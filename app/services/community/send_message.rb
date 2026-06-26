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

      pm_restriction = Community::CheckWarningRestrictions.call(user: @user, action: :pm)
      return pm_restriction if pm_restriction.failure?

      if Community::TrustLevel.contains_link?(@body) && !Community::TrustLevel.can_post_links?(@user)
        return ServiceResult.failure(error: "New members cannot post links. Participate more to unlock this.")
      end

      link_restriction = Community::CheckWarningRestrictions.call(user: @user, action: :link)
      return link_restriction if link_restriction.failure? && Community::TrustLevel.contains_link?(@body)

      others = @conversation.participants.where.not(user: @user).includes(:user).map(&:user)
      others.each do |other|
        if Community::UserBlock.blocked?(@user, other)
          return ServiceResult.failure(error: "You cannot message #{other.username}.")
        end
      end

      message = @conversation.messages.create!(user: @user, body: @body)
      @conversation.update!(last_message_at: message.created_at)
      @conversation.mark_read_for!(@user)
      @conversation.unarchive_all_participants!

      Community::NotifyPrivateMessage.call(message: message, conversation: @conversation)

      broadcast_message(message)

      ServiceResult.success(message)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def participant?
      @conversation.participants.exists?(user: @user)
    end

    # Push a small payload to the per-conversation stream so other participants
    # see the message live. Best-effort: a broadcast failure must never break
    # message sending.
    def broadcast_message(message)
      formatted = Community::FormatPostBody.call(body: message.body)
      body_html = formatted.success? ? formatted.value : ERB::Util.html_escape(message.body)

      Community::ConversationChannel.broadcast_to(
        @conversation,
        kind: "message",
        message: {
          id: message.id,
          body: message.body,
          body_html: body_html,
          author: @user.username,
          author_id: @user.id,
          avatar_url: @user.avatar_url,
          created_at: I18n.l(message.created_at, format: :short)
        }
      )
    rescue StandardError
      nil
    end
  end
end

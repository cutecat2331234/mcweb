# frozen_string_literal: true

module Community
  # Per-conversation stream for ephemeral real-time signals (typing indicators).
  # Only participants may subscribe.
  class ConversationChannel < ApplicationCable::Channel
    def subscribed
      conversation = find_conversation
      if conversation
        stream_for conversation
      else
        reject
      end
    end

    # Relay an ephemeral "typing" signal to the other participants (no persistence).
    def typing(_data)
      conversation = find_conversation
      return unless conversation

      ConversationChannel.broadcast_to(
        conversation,
        typing: true,
        user_id: current_user.id,
        username: current_user.username
      )
    end

    private

    def find_conversation
      conversation = Community::Conversation.find_by(id: params[:id])
      return nil unless conversation&.participants&.exists?(user_id: current_user.id)

      conversation
    end
  end
end

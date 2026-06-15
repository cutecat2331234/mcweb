# frozen_string_literal: true

module Community
  class ConversationParticipant < ApplicationRecord
    belongs_to :conversation, class_name: "Community::Conversation", foreign_key: :forum_conversation_id
    belongs_to :user

    def muted?
      muted_at.present?
    end
  end
end

# frozen_string_literal: true

module Community
  class Message < ApplicationRecord
    include SoftDeletable

    belongs_to :conversation, class_name: "Community::Conversation", foreign_key: :forum_conversation_id
    belongs_to :user

    validates :body, presence: true, length: { minimum: 1, maximum: 10_000 }

    after_create :touch_conversation

    def edited?
      edited_at.present?
    end

    private

    def touch_conversation
      conversation.update!(last_message_at: created_at)
    end
  end
end

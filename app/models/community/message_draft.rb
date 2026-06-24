# frozen_string_literal: true

module Community
  class MessageDraft < ApplicationRecord
    belongs_to :user
    belongs_to :conversation, class_name: "Community::Conversation", foreign_key: :forum_conversation_id

    validates :user_id, uniqueness: { scope: :forum_conversation_id }
  end
end

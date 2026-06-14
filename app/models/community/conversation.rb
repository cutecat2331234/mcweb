# frozen_string_literal: true

module Community
  class Conversation < ApplicationRecord
    has_many :participants, class_name: "Community::ConversationParticipant", foreign_key: :forum_conversation_id, dependent: :destroy
    has_many :users, through: :participants
    has_many :messages, class_name: "Community::Message", foreign_key: :forum_conversation_id, dependent: :destroy

    scope :for_user, ->(user) {
      joins(:participants).where(forum_conversation_participants: { user_id: user.id })
    }

    scope :ordered, -> { order(last_message_at: :desc) }

    def other_user(current_user)
      users.where.not(id: current_user.id).first
    end

    def unread_count_for(user)
      participant = participants.find_by(user: user)
      return 0 unless participant

      scope = messages.where.not(user: user)
      scope = scope.where("created_at > ?", participant.last_read_at) if participant.last_read_at
      scope.count
    end

    def mark_read_for!(user)
      participants.find_by(user: user)&.update!(last_read_at: Time.current)
    end
  end
end

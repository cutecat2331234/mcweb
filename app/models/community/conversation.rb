# frozen_string_literal: true

module Community
  class Conversation < ApplicationRecord
    has_many :participants, class_name: "Community::ConversationParticipant", foreign_key: :forum_conversation_id, dependent: :destroy
    has_many :users, through: :participants
    has_many :messages, class_name: "Community::Message", foreign_key: :forum_conversation_id, dependent: :destroy
    belongs_to :creator, class_name: "User", optional: true

    scope :for_user, ->(user, include_archived: false) {
      scope = joins(:participants).where(forum_conversation_participants: { user_id: user.id })
      scope = scope.where(forum_conversation_participants: { archived_at: nil }) unless include_archived
      scope
    }

    scope :ordered, -> { order(last_message_at: :desc) }

    def display_name(current_user)
      return title if is_group? && title.present?

      other_user(current_user)&.username || "私信"
    end

    def participant_names
      users.pluck(:username).join(", ")
    end

    def other_user(current_user)
      users.where.not(id: current_user.id).first
    end

    def unread_count_for(user)
      participant = participants.find_by(user: user)
      return 0 unless participant
      return 0 if participant.muted_at.present?

      scope = messages.where.not(user: user)
      scope = scope.where("created_at > ?", participant.last_read_at) if participant.last_read_at
      scope.count
    end

    def mark_read_for!(user)
      participants.find_by(user: user)&.update!(last_read_at: Time.current)
    end

    def unarchive_all_participants!
      participants.where.not(archived_at: nil).update_all(archived_at: nil)
    end

    def participant?(user)
      participants.exists?(user: user)
    end

    def self.unread_counts_for(user, conversation_ids)
      return {} if conversation_ids.blank?

      counts = Community::Message
        .joins(conversation: :participants)
        .where(forum_conversation_id: conversation_ids)
        .where(forum_conversation_participants: { user_id: user.id, muted_at: nil })
        .where.not(user_id: user.id)
        .where(
          "forum_conversation_participants.last_read_at IS NULL " \
          "OR forum_messages.created_at > forum_conversation_participants.last_read_at"
        )
        .group(:forum_conversation_id)
        .count
        .transform_keys(&:to_i)

      conversation_ids.index_with { |id| counts[id] || 0 }
    end

    def self.total_unread_count_for(user)
      Community::Message
        .joins(conversation: :participants)
        .where(forum_conversation_participants: { user_id: user.id, archived_at: nil, muted_at: nil })
        .where.not(user_id: user.id)
        .where(
          "forum_conversation_participants.last_read_at IS NULL " \
          "OR forum_messages.created_at > forum_conversation_participants.last_read_at"
        )
        .count
    end
  end
end

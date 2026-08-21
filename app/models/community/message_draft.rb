# frozen_string_literal: true

module Community
  class MessageDraft < ApplicationRecord
    belongs_to :user
    belongs_to :conversation, class_name: "Community::Conversation", foreign_key: :forum_conversation_id

    validates :user_id, uniqueness: { scope: :forum_conversation_id }
    validate :attachment_ids_are_bounded_integers

    def normalized_attachment_ids
      Array(attachment_ids).filter_map { |id| Integer(id, exception: false) }.uniq
    end

    private

    def attachment_ids_are_bounded_integers
      normalized = normalized_attachment_ids
      errors.add(:attachment_ids, :invalid) unless normalized.size == Array(attachment_ids).size
      errors.add(:attachment_ids, :too_long, count: 10) if normalized.size > 10
    end
  end
end

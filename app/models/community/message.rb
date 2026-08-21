# frozen_string_literal: true

module Community
  class Message < ApplicationRecord
    include SoftDeletable

    belongs_to :conversation, class_name: "Community::Conversation", foreign_key: :forum_conversation_id
    belongs_to :user
    # The database FK cascade removes revisions only after the parent row is
    # deleted by the governed purge path; ordinary revision deletion is blocked.
    has_many :revisions,
      class_name: "Community::MessageRevision",
      foreign_key: :forum_message_id,
      inverse_of: :message
    has_many :attachments,
      class_name: "Community::PostAttachment",
      foreign_key: :forum_message_id,
      inverse_of: :message,
      dependent: :destroy

    validates :body, presence: true, length: { minimum: 1, maximum: 10_000 }
    validates :revision, numericality: { only_integer: true, greater_than: 0 }

    after_create :record_initial_revision
    after_create :touch_conversation

    def edited?
      edited_at.present?
    end

    private

    def record_initial_revision
      revisions.create!(
        editor: user,
        revision: revision,
        body: body,
        content_digest: Digest::SHA256.hexdigest(body)
      )
    end

    def touch_conversation
      conversation.update!(last_message_at: created_at)
    end
  end
end

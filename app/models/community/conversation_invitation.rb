# frozen_string_literal: true

module Community
  class ConversationInvitation < ApplicationRecord
    include HasPublicId

    DEFAULT_EXPIRY = 7.days
    STATUSES = %w[pending accepted declined expired revoked].freeze

    belongs_to :conversation,
      class_name: "Community::Conversation",
      foreign_key: :forum_conversation_id,
      inverse_of: :invitations
    belongs_to :user
    belongs_to :invited_by, class_name: "User"

    enum :status, STATUSES.index_with(&:itself), validate: true

    validates :expires_at, presence: true
    validates :user_id,
      uniqueness: {
        scope: :forum_conversation_id,
        conditions: -> { where(status: "pending") }
      },
      if: :pending?
    validate :group_conversation_only
    validate :resolved_at_matches_status

    scope :pending_actionable, -> {
      where(status: "pending").where("expires_at > ?", Time.current)
    }

    def actionable?(at: Time.current)
      pending? && expires_at.present? && expires_at > at
    end

    def blocked_by_participant?
      blocked_ids = Community::UserBlock.blocked_user_ids(user)
      blocked_ids.include?(invited_by_id) ||
        (blocked_ids.any? && conversation.participants.where(user_id: blocked_ids).exists?)
    end

    private

    def group_conversation_only
      errors.add(:conversation, :invalid) unless conversation&.is_group?
    end

    def resolved_at_matches_status
      if pending? && resolved_at.present?
        errors.add(:resolved_at, :invalid)
      elsif !pending? && resolved_at.blank?
        errors.add(:resolved_at, :blank)
      end
    end
  end
end

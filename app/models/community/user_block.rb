# frozen_string_literal: true

module Community
  class UserBlock < ApplicationRecord
    belongs_to :blocker, class_name: "User"
    belongs_to :blocked, class_name: "User"

    validates :blocker_id, uniqueness: { scope: :blocked_id }

    def self.blocked?(viewer, author)
      return false unless viewer && author

      exists?(blocker: viewer, blocked: author) || exists?(blocker: author, blocked: viewer)
    end

    def self.blocked_user_ids(user)
      return [] unless user

      blocked_ids = where(blocker: user).pluck(:blocked_id)
      blocker_ids = where(blocked: user).pluck(:blocker_id)
      (blocked_ids + blocker_ids).uniq
    end
  end
end

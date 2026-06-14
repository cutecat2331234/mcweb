# frozen_string_literal: true

module Community
  class UserFollow < ApplicationRecord
    belongs_to :follower, class_name: "User"
    belongs_to :followed, class_name: "User"

    validates :follower_id, uniqueness: { scope: :followed_id }
    validate :cannot_follow_self

    private

    def cannot_follow_self
      errors.add(:followed_id, "cannot follow yourself") if follower_id == followed_id
    end
  end
end

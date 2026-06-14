# frozen_string_literal: true

module Community
  class UserWarning < ApplicationRecord
    self.table_name = "forum_user_warnings"

    belongs_to :user
    belongs_to :issuer, class_name: "User"

    validates :reason, presence: true
    validates :points, numericality: { greater_than: 0, less_than_or_equal_to: 10 }

    scope :recent, -> { order(created_at: :desc) }

    def self.total_points_for(user)
      where(user: user).sum(:points)
    end
  end
end

# frozen_string_literal: true

module Community
  class UserWarning < ApplicationRecord
    self.table_name = "forum_user_warnings"

    belongs_to :user
    belongs_to :issuer, class_name: "User"

    validates :reason, presence: true
    validates :points, numericality: { greater_than: 0, less_than_or_equal_to: 10 }

    scope :recent, -> { order(created_at: :desc) }
    scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

    def self.total_points_for(user)
      active.where(user: user).sum(:points)
    end

    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    def active?
      !expired?
    end
  end
end

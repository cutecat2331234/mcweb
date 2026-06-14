# frozen_string_literal: true

module Community
  class Badge < ApplicationRecord
    self.table_name = "forum_badges"

    GRANT_RULES = %w[manual first_topic posts_count likes_received].freeze

    has_many :user_badges, class_name: "Community::UserBadge", foreign_key: :forum_badge_id, dependent: :destroy
    has_many :users, through: :user_badges

    validates :name, :slug, presence: true
    validates :slug, uniqueness: true
    validates :grant_rule, inclusion: { in: GRANT_RULES }
  end
end

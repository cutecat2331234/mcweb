# frozen_string_literal: true

module Community
  class Badge < ApplicationRecord
    self.table_name = "forum_badges"

    GRANT_RULES = %w[manual first_topic posts_count likes_received first_purchase trust_level member_days solutions topics_count reactions_given first_reply].freeze
    TIERS = %w[bronze silver gold].freeze

    has_many :user_badges, class_name: "Community::UserBadge", foreign_key: :forum_badge_id, dependent: :destroy
    has_many :users, through: :user_badges

    validates :name, :slug, presence: true
    validates :slug, uniqueness: true
    validates :grant_rule, inclusion: { in: GRANT_RULES }
    validates :tier, inclusion: { in: TIERS }
  end
end

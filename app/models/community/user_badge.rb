# frozen_string_literal: true

module Community
  class UserBadge < ApplicationRecord
    self.table_name = "forum_user_badges"

    belongs_to :user
    belongs_to :badge, class_name: "Community::Badge", foreign_key: :forum_badge_id

    validates :user_id, uniqueness: { scope: :forum_badge_id }
  end
end

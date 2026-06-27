# frozen_string_literal: true

module Community
  # A single daily check-in row. One per (user, calendar day), enforced by a
  # unique index on [:user_id, :checked_on]. `streak` is the consecutive-day
  # count *as of that day*; `points_awarded` is the total (base + milestone
  # bonus) granted for that check-in. See Community::DailyCheckIn for the rules.
  class CheckIn < ApplicationRecord
    self.table_name = "forum_check_ins"

    belongs_to :user

    validates :checked_on, presence: true
    validates :streak, numericality: { only_integer: true, greater_than: 0 }
    validates :points_awarded, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :checked_on, uniqueness: { scope: :user_id }
  end
end

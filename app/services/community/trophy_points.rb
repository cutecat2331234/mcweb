# frozen_string_literal: true

module Community
  # XenForo-style "trophy points": each earned badge contributes points based on
  # its tier. Computed from existing badges, no extra storage.
  module TrophyPoints
    TIER_POINTS = {
      "bronze" => 5,
      "silver" => 15,
      "gold" => 30
    }.freeze

    DEFAULT_POINTS = 5

    module_function

    def for_user(user)
      return 0 unless user

      tiers = if user.user_badges.loaded?
                user.user_badges.filter_map { |ub| ub.badge&.tier }
      else
                user.user_badges.joins(:badge).pluck("forum_badges.tier")
      end

      tiers.sum { |tier| TIER_POINTS.fetch(tier, DEFAULT_POINTS) }
    end
  end
end

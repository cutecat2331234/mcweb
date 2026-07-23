# frozen_string_literal: true

module Community
  # XenForo-style managed reaction. When at least one active reaction type exists,
  # it becomes the single source of truth for the allowed reaction emoji and their
  # weighted scores (used by ToggleReaction and the reaction leaderboard). When the
  # table is empty the app falls back to the legacy SiteSetting-based configuration,
  # so this is fully backward compatible.
  class ReactionType < ApplicationRecord
    self.table_name = "forum_reaction_types"

    MAX_EMOJI = 24

    validates :emoji, presence: true, uniqueness: true
    validates :name, presence: true
    validates :score, numericality: { only_integer: true }

    scope :active, -> { where(active: true) }
    scope :ordered, -> { order(:position, :id) }

    # True when an admin has configured managed reaction types.
    def self.configured?
      active.exists?
    end

    # Ordered list of active reaction emoji (the allowed set).
    def self.emojis
      active.ordered.limit(MAX_EMOJI).pluck(:emoji)
    end

    # emoji => score weighting for active reaction types.
    def self.score_map
      active.pluck(:emoji, :score).to_h
    end
  end
end

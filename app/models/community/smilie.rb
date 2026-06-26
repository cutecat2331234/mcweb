# frozen_string_literal: true

module Community
  # XenForo-style smilie: a text code (":)") substituted with an emoji/character
  # when rendering post bodies. Cached; empty until an admin defines smilies, so
  # the substitution is a no-op for existing content until opted into.
  class Smilie < ApplicationRecord
    self.table_name = "community_smilies"

    CACHE_KEY = "community/smilies/replacements"

    validates :code, presence: true, uniqueness: true, length: { maximum: 40 }
    validates :emoji, presence: true, length: { maximum: 40 }

    scope :active, -> { where(active: true) }
    scope :ordered, -> { order(position: :asc, code: :asc) }

    after_commit :clear_cache

    # Longest codes first so e.g. ":))" wins over ":)".
    def self.replacements
      Rails.cache.fetch(CACHE_KEY) do
        active.pluck(:code, :emoji).sort_by { |code, _| -code.length }
      end
    end

    def self.clear_cache!
      Rails.cache.delete(CACHE_KEY)
    end

    private

    def clear_cache
      self.class.clear_cache!
    end
  end
end

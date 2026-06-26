# frozen_string_literal: true

module Community
  # XenForo-style admin-defined custom BBCode. `replacement` is a Markdown
  # template containing {content}; rendering still passes through the Markdown
  # pipeline + sanitizer, so no raw HTML is trusted. Cached; no-op until defined.
  class CustomBbcode < ApplicationRecord
    self.table_name = "community_custom_bbcodes"

    CACHE_KEY = "community/custom_bbcodes"

    validates :tag, presence: true, uniqueness: true,
              format: { with: /\A[a-z0-9]+\z/, message: :invalid_tag }
    validates :replacement, presence: true

    scope :active, -> { where(active: true) }
    scope :ordered, -> { order(:tag) }

    after_commit :clear_cache

    # [[tag, replacement], ...] of active codes, cached.
    def self.definitions
      Rails.cache.fetch(CACHE_KEY) do
        active.pluck(:tag, :replacement)
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

# frozen_string_literal: true

module Community
  # XenForo-style forum theme: a small set of color tokens applied as CSS
  # variables on the portal root. Only the active default theme is applied;
  # with none, the portal's built-in defaults are used (no override).
  class ForumTheme < ApplicationRecord
    self.table_name = "community_forum_themes"

    CACHE_KEY = "community/forum_theme/active"
    # Only allow simple, safe CSS color values as token overrides.
    COLOR_FORMAT = /\A#(?:\h{3}|\h{6})\z|\Aoklch\([\d.\s%]+\)\z|\Argba?\([\d.,\s%]+\)\z/i

    validates :name, presence: true, length: { maximum: 100 }
    validates :primary_color, :accent_color,
              format: { with: COLOR_FORMAT, message: :invalid_color }, allow_blank: true

    scope :ordered, -> { order(is_default: :desc, name: :asc) }

    after_commit :clear_cache

    # CSS-variable token hash for the active default theme (cached). Empty when none.
    def self.active_tokens
      Rails.cache.fetch(CACHE_KEY) do
        theme = where(active: true, is_default: true).order(:id).first
        next {} unless theme

        tokens = {}
        tokens["--primary"] = theme.primary_color if theme.primary_color.present?
        tokens["--accent"] = theme.accent_color if theme.accent_color.present?
        tokens
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

# frozen_string_literal: true

module Community
  # XenForo-style custom "page node": admin-managed standalone content page,
  # optionally surfaced as a forum nav item.
  class ForumPage < ApplicationRecord
    self.table_name = "community_forum_pages"

    NAV_CACHE_KEY = "community/forum_pages/nav"

    validates :title, presence: true, length: { maximum: 200 }
    validates :slug, presence: true, uniqueness: true,
              format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, message: :invalid_slug }

    before_validation :generate_slug, on: :create
    after_commit :clear_nav_cache

    scope :published, -> { where(published: true) }
    scope :ordered, -> { order(position: :asc, title: :asc) }
    scope :in_nav, -> { published.where(show_in_nav: true).order(position: :asc) }

    # [{ label:, slug: }] for nav-flagged pages, cached.
    def self.nav_items
      Rails.cache.fetch(NAV_CACHE_KEY) do
        in_nav.map { |page| { "label" => page.nav_label.presence || page.title, "slug" => page.slug } }
      end
    end

    def self.clear_nav_cache!
      Rails.cache.delete(NAV_CACHE_KEY)
    end

    private

    def generate_slug
      return if slug.present?

      base = title.to_s.parameterize
      base = "page-#{SecureRandom.hex(3)}" if base.blank?
      candidate = base
      i = 2
      while Community::ForumPage.exists?(slug: candidate)
        candidate = "#{base}-#{i}"
        i += 1
      end
      self.slug = candidate
    end

    def clear_nav_cache
      self.class.clear_nav_cache!
    end
  end
end

# frozen_string_literal: true

module Community
  # XenForo-style help center article.
  class HelpArticle < ApplicationRecord
    self.table_name = "community_help_articles"

    validates :title, presence: true, length: { maximum: 200 }
    validates :slug, presence: true, uniqueness: true,
              format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, message: :invalid_slug }
    validates :category, presence: true

    before_validation :generate_slug, on: :create

    scope :published, -> { where(published: true) }
    scope :ordered, -> { order(category: :asc, position: :asc, title: :asc) }

    private

    def generate_slug
      return if slug.present?

      base = title.to_s.parameterize
      base = "help-#{SecureRandom.hex(3)}" if base.blank?
      candidate = base
      i = 2
      while Community::HelpArticle.exists?(slug: candidate)
        candidate = "#{base}-#{i}"
        i += 1
      end
      self.slug = candidate
    end
  end
end

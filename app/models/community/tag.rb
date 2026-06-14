# frozen_string_literal: true

module Community
  class Tag < ApplicationRecord
    has_many :topic_tags, class_name: "Community::TopicTag", foreign_key: :forum_tag_id, dependent: :destroy
    has_many :topics, through: :topic_tags, source: :topic

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: true

    before_validation :generate_slug, on: :create

    scope :ordered, -> { order(:name) }

    def self.find_or_create_by_name!(name)
      normalized = name.to_s.strip
      return if normalized.blank?

      slug = normalized.parameterize.presence || "tag-#{SecureRandom.hex(4)}"
      find_or_create_by!(slug: slug) { |tag| tag.name = normalized }
    end

    private

    def generate_slug
      self.slug = name.to_s.parameterize.presence || "tag-#{SecureRandom.hex(4)}"
    end
  end
end

# frozen_string_literal: true

module Community
  class TagGroup < ApplicationRecord
    has_many :memberships, class_name: "Community::TagGroupMembership", foreign_key: :forum_tag_group_id, dependent: :destroy
    has_many :tags, through: :memberships, source: :tag

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: true

    before_validation :generate_slug, on: :create

    scope :ordered, -> { order(:name) }

    def tag_ids
      tags.pluck(:id)
    end

    private

    def generate_slug
      self.slug = name.to_s.parameterize.presence || "group-#{SecureRandom.hex(4)}" if slug.blank?
    end
  end
end

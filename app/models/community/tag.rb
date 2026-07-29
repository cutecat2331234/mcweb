# frozen_string_literal: true

module Community
  class Tag < ApplicationRecord
    belongs_to :canonical_tag, class_name: "Community::Tag", optional: true
    has_many :synonyms, class_name: "Community::Tag", foreign_key: :canonical_tag_id, dependent: :nullify
    has_many :topic_tags, class_name: "Community::TopicTag", foreign_key: :forum_tag_id, dependent: :destroy
    has_many :topics, through: :topic_tags, source: :topic
    has_many :tag_group_memberships, class_name: "Community::TagGroupMembership", foreign_key: :forum_tag_id, dependent: :destroy
    has_many :tag_groups, through: :tag_group_memberships, source: :tag_group

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: true
    validate :canonical_tag_valid

    before_validation :generate_slug, on: :create

    scope :ordered, -> { order(:name) }

    def self.resolve_by_slug(slug)
      tag = find_by(slug: slug)
      return nil unless tag

      tag.canonical_tag || tag
    end

    # Resolving an alias must not bypass the visibility of either the alias or
    # its canonical tag. This is the read-side counterpart to usable_by and is
    # used by search, RSS, oneboxes, and subscription surfaces.
    def self.resolve_by_slug_for(slug, user:)
      resolve_usable_candidate(usable_by(user).find_by(slug: slug), user: user)
    end

    def self.resolve_by_slug_or_name_for(value, user:)
      scope = usable_by(user)
      candidate = scope.find_by(slug: value) || scope.find_by(name: value)
      resolve_usable_candidate(candidate, user: user)
    end

    def effective_tag
      canonical_tag || self
    end

    def self.usable_by(user)
      staff = user&.permission?("forum.tags.manage") || user&.permission?("admin.access")
      staff ? all : where(staff_only: false)
    end

    def self.find_or_create_by_name!(name, user: nil)
      normalized = name.to_s.strip
      return if normalized.blank?

      slug = normalized.parameterize.presence || "tag-#{SecureRandom.hex(4)}"
      existing = find_by(slug: slug)
      return existing if existing
      return if existing.nil? && staff_only_tag_requested?(normalized, user)

      create!(slug: slug, name: normalized)
    end

    def self.staff_only_tag_requested?(normalized, user)
      false
    end

    def self.resolve_usable_candidate(candidate, user:)
      return unless candidate

      usable_by(user).find_by(id: candidate.effective_tag.id)
    end
    private_class_method :resolve_usable_candidate

    private

    def generate_slug
      self.slug = name.to_s.parameterize.presence || "tag-#{SecureRandom.hex(4)}"
    end

    def canonical_tag_valid
      return if canonical_tag_id.blank?

      if persisted? && canonical_tag_id == id
        errors.add(:canonical_tag_id, I18n.t("mcweb.validation_errors.cannot_be_self"))
      end
    end
  end
end

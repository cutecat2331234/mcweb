module Community
  class Section < ApplicationRecord
    belongs_to :category, class_name: "Community::Category", foreign_key: :forum_category_id
    belongs_to :parent, class_name: "Community::Section", optional: true
    has_many :children, class_name: "Community::Section", foreign_key: :parent_id, dependent: :destroy
    has_many :topics, class_name: "Community::Topic", foreign_key: :forum_section_id, dependent: :destroy
    has_many :mutes, class_name: "Community::Mute", foreign_key: :forum_section_id, dependent: :destroy
    has_many :subscriptions, as: :subscribable, class_name: "Community::Subscription", dependent: :destroy

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: { scope: :forum_category_id }

    scope :ordered, -> { order(:position) }
    scope :roots, -> { where(parent_id: nil) }

    def allowed?(user, action)
      return false unless trust_allowed?(user, action)

      perms = permissions[action.to_s]
      return true if perms.blank?

      user && perms.any? { |role_key| user.permission?(role_key) }
    end

    def trust_allowed?(user, action)
      min_level = case action.to_sym
      when :create_topic then min_trust_level_create.to_i
      when :reply then min_trust_level_reply.to_i
      else 0
      end
      return true if min_level <= 0
      return false unless user

      Community::TrustLevel.level_for(user) >= min_level
    end

    def min_trust_label(action)
      level = action == :create_topic ? min_trust_level_create.to_i : min_trust_level_reply.to_i
      entry = Community::TrustLevel::LEVELS.find { |item| item[:level] == level }
      entry ? "#{entry[:name]} (Lv.#{level})" : "Lv.#{level}"
    end

    def to_param
      slug
    end

    def required_tags
      ids = Array(required_tag_ids).map(&:to_i).reject(&:zero?)
      return Community::Tag.none if ids.empty?

      Community::Tag.where(id: ids).order(:name)
    end

    def default_tags
      ids = Array(default_tag_ids).map(&:to_i).reject(&:zero?)
      return Community::Tag.none if ids.empty?

      Community::Tag.where(id: ids).order(:name)
    end

    def allowed_tags
      ids = Array(allowed_tag_ids).map(&:to_i).reject(&:zero?)
      return Community::Tag.none if ids.empty?

      Community::Tag.where(id: ids).order(:name)
    end

    def read_only?
      read_only == true
    end

    def writable_by?(user, action)
      return true unless read_only?
      return true if user&.permission?("forum.topics.lock") || user&.permission?("admin.access")

      false
    end
  end
end

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
      perms = permissions[action.to_s]
      return true if perms.blank?

      user && perms.any? { |role_key| user.permission?(role_key) }
    end

    def to_param
      slug
    end

    def required_tags
      ids = Array(required_tag_ids).map(&:to_i).reject(&:zero?)
      return Community::Tag.none if ids.empty?

      Community::Tag.where(id: ids).order(:name)
    end
  end
end

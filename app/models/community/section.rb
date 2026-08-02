module Community
  class Section < ApplicationRecord
    belongs_to :category, class_name: "Community::Category", foreign_key: :forum_category_id
    belongs_to :parent, class_name: "Community::Section", optional: true
    belongs_to :archived_by, class_name: "User", optional: true
    has_many :children, class_name: "Community::Section", foreign_key: :parent_id, dependent: :restrict_with_error
    has_many :topics, class_name: "Community::Topic", foreign_key: :forum_section_id, dependent: :restrict_with_error
    has_many :mutes, class_name: "Community::Mute", foreign_key: :forum_section_id, dependent: :destroy
    has_many :subscriptions, as: :subscribable, class_name: "Community::Subscription", dependent: :destroy
    has_many :section_moderators, class_name: "Community::SectionModerator", foreign_key: :forum_section_id, dependent: :destroy
    has_many :section_mutes, class_name: "Community::SectionMute", foreign_key: :forum_section_id, dependent: :destroy
    has_many :moderation_cases, class_name: "Community::ModerationCase", foreign_key: :forum_section_id, dependent: :restrict_with_error
    has_many :moderators, through: :section_moderators, source: :user

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: { scope: :forum_category_id }
    validates :archived_reason, length: { maximum: 1_000 }, allow_blank: true
    validate :parent_hierarchy_is_valid

    scope :ordered, -> { order(:position) }
    scope :roots, -> { where(parent_id: nil) }
    scope :active, -> { where(archived_at: nil) }
    scope :archived, -> { where.not(archived_at: nil) }

    def self.effectively_active
      active_sections = active.includes(:parent).to_a
      where(id: active_sections.filter_map { |section| section.id if section.publicly_active? })
    end

    def self_archived?
      archived_at.present?
    end

    def archived_ancestor
      section = parent
      visited_ids = []

      while section
        return section if section.archived_at.present?
        return nil if section.id.present? && visited_ids.include?(section.id)

        visited_ids << section.id if section.id.present?
        section = section.parent
      end

      nil
    end

    def inherited_archived?
      !self_archived? && archived_ancestor.present?
    end

    def lifecycle_status
      return :self_archived if self_archived?
      return :inherited_archived if inherited_archived?

      :effectively_active
    end

    def publicly_active?
      section = self
      visited_ids = []

      while section
        return false if section.archived_at.present?
        return false if section.id.present? && visited_ids.include?(section.id)

        visited_ids << section.id if section.id.present?
        section = section.parent
      end

      true
    end

    def allowed?(user, action)
      return false unless trust_allowed?(user, action)

      perms = permissions[action.to_s]
      return true if perms.blank?

      user && perms.any? { |role_key| user.permission?(role_key) }
    end

    def trust_allowed?(user, action)
      return true if user && Mcweb::DeveloperMode.allow?(:skip_anti_spam)

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

    def required_tag_groups
      ids = Array(required_tag_group_ids).map(&:to_i).reject(&:zero?)
      return Community::TagGroup.none if ids.empty?

      Community::TagGroup.where(id: ids).order(:name)
    end

    def requires_tags_or_groups?
      Array(required_tag_ids).map(&:to_i).reject(&:zero?).any? ||
        Array(required_tag_group_ids).map(&:to_i).reject(&:zero?).any?
    end

    def tag_requirements_message
      parts = []
      if Array(required_tag_ids).map(&:to_i).reject(&:zero?).any?
        names = required_tags.pluck(:name).join("、")
        parts << "至少包含以下标签之一：#{names}"
      end
      if Array(required_tag_group_ids).map(&:to_i).reject(&:zero?).any?
        names = required_tag_groups.pluck(:name).join("、")
        parts << "从以下标签组中至少选一个标签：#{names}"
      end
      "此分区要求#{parts.join('；')}"
    end

    def read_only?
      read_only == true
    end

    def writable_by?(user, action)
      return true unless read_only?
      return true if Community::SectionModeration.can_moderate?(user: user, section: self)

      false
    end

    def moderator?(user)
      Community::SectionModeration.section_moderator?(user, self)
    end

    def login_required?
      login_required == true
    end

    def visible_to?(user)
      return true unless login_required?

      user.present?
    end

    def prefix_definitions
      Community::SectionPrefixes.normalize(prefixes)
    end

    def prefix_names
      Community::SectionPrefixes.names(prefixes)
    end

    def prefix_color_for(name)
      Community::SectionPrefixes.color_for(prefixes, name)
    end

    def prefix_options
      Community::SectionPrefixes.serialize_options(prefixes)
    end

    private

    def parent_hierarchy_is_valid
      if parent
        errors.add(:parent, :invalid) if parent.forum_category_id != forum_category_id

        candidate = parent
        visited_ids = []
        while candidate
          if id.present? && candidate.id == id
            errors.add(:parent, :invalid)
            break
          end
          break if candidate.id.present? && visited_ids.include?(candidate.id)

          visited_ids << candidate.id if candidate.id.present?
          candidate = candidate.parent
        end
      end

      return unless persisted? && will_save_change_to_forum_category_id?
      return unless children.where.not(forum_category_id: forum_category_id).exists?

      errors.add(:category, :invalid)
    end
  end
end

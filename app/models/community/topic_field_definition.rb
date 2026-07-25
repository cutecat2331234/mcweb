# frozen_string_literal: true

module Community
  class TopicFieldDefinition < ApplicationRecord
    self.table_name = "forum_topic_field_definitions"

    FIELD_TYPES = %w[text textarea number url select checkbox].freeze
    DISPLAY_LOCATIONS = %w[before_message after_message topic_status].freeze
    PLUGIN_ID_PATTERN = /\A[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\/[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\z/

    has_many :values,
      class_name: "Community::TopicFieldValue",
      foreign_key: :forum_topic_field_definition_id,
      dependent: :destroy,
      inverse_of: :definition

    before_validation :normalize_key
    before_validation :normalize_owner_plugin_id
    before_validation :normalize_id_lists

    validates :key, presence: true, uniqueness: true, format: { with: /\A[a-z][a-z0-9_]*\z/ }
    validates :label, presence: true
    validates :field_type, inclusion: { in: FIELD_TYPES }
    validates :display_location, inclusion: { in: DISPLAY_LOCATIONS }
    validates :sort_order, numericality: { only_integer: true }
    validates :owner_plugin_id,
      format: { with: PLUGIN_ID_PATTERN },
      allow_blank: true
    validate :choices_are_present_for_select
    validate :key_is_immutable, on: :update

    scope :active, -> { where(active: true) }
    scope :ordered, -> { order(:sort_order, :key) }

    def choice_list
      choices.to_s.split(/\r?\n/).map(&:strip).reject(&:blank?).uniq
    end

    def applicable_to_section?(section)
      ids = normalized_ids(section_ids)
      ids.empty? || (section.present? && ids.include?(section.id))
    end

    def editable_by?(user)
      return false unless editable_by_user?

      ids = normalized_ids(editable_group_ids)
      return true if ids.empty?
      return false unless user

      Community::GroupMembership.where(
        user_id: user.id,
        community_user_group_id: ids
      ).exists?
    end

    private

    def normalize_key
      self.key = key.to_s.strip.downcase
    end

    def normalize_owner_plugin_id
      self.owner_plugin_id = owner_plugin_id.to_s.strip.downcase.presence
    end

    def normalize_id_lists
      self.section_ids = normalized_ids(section_ids)
      self.editable_group_ids = normalized_ids(editable_group_ids)
    end

    def normalized_ids(value)
      Array(value)
        .flat_map { |item| item.to_s.split(/[\s,]+/) }
        .filter_map { |item| Integer(item, exception: false) }
        .select(&:positive?)
        .uniq
    end

    def key_is_immutable
      errors.add(:key, "cannot be changed after creation") if will_save_change_to_key?
    end

    def choices_are_present_for_select
      return unless field_type == "select" && choice_list.empty?

      errors.add(:choices, "must contain at least one option")
    end
  end
end

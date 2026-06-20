# frozen_string_literal: true

module Community
  class UserFieldDefinition < ApplicationRecord
    self.table_name = "forum_user_field_definitions"

    FIELD_TYPES = %w[text textarea number url select checkbox].freeze
    VISIBILITIES = %w[public owner staff].freeze

    has_many :values, class_name: "Community::UserFieldValue", foreign_key: :forum_user_field_definition_id, dependent: :destroy

    validates :key, presence: true, uniqueness: true, format: { with: /\A[a-z][a-z0-9_]*\z/ }
    validates :label, presence: true
    validates :field_type, inclusion: { in: FIELD_TYPES }
    validates :visibility, inclusion: { in: VISIBILITIES }

    scope :active, -> { where(active: true) }
    scope :ordered, -> { order(:sort_order, :key) }
    scope :for_registration, -> { active.where(show_on_registration: true) }
    scope :for_profile, -> { active.where(show_on_profile: true) }

    def choice_list
      choices.to_s.split(/\r?\n/).map(&:strip).reject(&:blank?)
    end
  end
end

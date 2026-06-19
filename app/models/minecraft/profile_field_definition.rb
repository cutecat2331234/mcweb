# frozen_string_literal: true

module Minecraft
  class ProfileFieldDefinition < ApplicationRecord
    FIELD_TYPES = %w[text number url markdown badge link json].freeze
    VISIBILITIES = %w[public owner staff].freeze

    validates :key, presence: true, uniqueness: true
    validates :label, presence: true
    validates :field_type, inclusion: { in: FIELD_TYPES }
    validates :visibility, inclusion: { in: VISIBILITIES }

    scope :active, -> { where(active: true) }
    scope :ordered, -> { order(:sort_order, :key) }
  end
end

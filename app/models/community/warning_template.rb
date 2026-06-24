# frozen_string_literal: true

module Community
  # Admin-defined preset for issuing user warnings (XenForo "warning definitions"):
  # a reusable name, reason, point value, and expiry that pre-fill a new warning.
  class WarningTemplate < ApplicationRecord
    validates :name, presence: true
    validates :points, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }

    scope :ordered, -> { order(:position, :name) }
  end
end

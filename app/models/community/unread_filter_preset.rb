# frozen_string_literal: true

module Community
  class UnreadFilterPreset < ApplicationRecord
    self.table_name = "forum_unread_filter_presets"

    belongs_to :user

    validates :name, presence: true

    scope :recent, -> { order(created_at: :desc) }
  end
end

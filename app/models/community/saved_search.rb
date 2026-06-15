# frozen_string_literal: true

module Community
  class SavedSearch < ApplicationRecord
    self.table_name = "forum_saved_searches"

    belongs_to :user

    validates :name, presence: true
    validates :query, presence: true, allow_blank: true

    scope :recent, -> { order(created_at: :desc) }
    scope :notify_daily, -> { where(notify_daily: true) }
  end
end

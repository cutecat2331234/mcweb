# frozen_string_literal: true

module Commerce
  class WishlistFilterPreset < ApplicationRecord
    self.table_name = "store_wishlist_filter_presets"

    belongs_to :user

    validates :name, presence: true

    scope :recent, -> { order(created_at: :desc) }
  end
end

# frozen_string_literal: true

module Commerce
  class WishlistItem < ApplicationRecord
    belongs_to :user
    belongs_to :product, class_name: "Commerce::Product", foreign_key: :store_product_id
    belongs_to :variant, class_name: "Commerce::ProductVariant", foreign_key: :variant_id, optional: true

    validates :user_id, uniqueness: { scope: :store_product_id }
  end
end

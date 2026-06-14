# frozen_string_literal: true

module Commerce
  class StockAlert < ApplicationRecord
    belongs_to :user
    belongs_to :product, class_name: "Commerce::Product", foreign_key: :store_product_id
    belongs_to :variant, class_name: "Commerce::ProductVariant", foreign_key: :store_product_variant_id, optional: true

    validates :user_id, uniqueness: { scope: [ :store_product_id, :store_product_variant_id ] }
  end
end

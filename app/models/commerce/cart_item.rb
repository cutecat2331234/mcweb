module Commerce
  class CartItem < ApplicationRecord
    belongs_to :cart, class_name: "Commerce::Cart", foreign_key: :store_cart_id
    belongs_to :product, class_name: "Commerce::Product", foreign_key: :store_product_id
    belongs_to :variant, class_name: "Commerce::ProductVariant", foreign_key: :store_product_variant_id, optional: true

    validates :quantity, numericality: { only_integer: true, greater_than: 0 }
    validates :store_product_id, uniqueness: { scope: [ :store_cart_id, :store_product_variant_id ] }

    def unit_price_cents
      variant&.price_cents || product.price_cents
    end

    def total_cents
      unit_price_cents * quantity
    end
  end
end

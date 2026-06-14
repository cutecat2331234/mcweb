module Commerce
  class OrderItem < ApplicationRecord
    belongs_to :order, class_name: "Commerce::Order", foreign_key: :store_order_id
    belongs_to :product, class_name: "Commerce::Product", foreign_key: :store_product_id, optional: true
    belongs_to :variant, class_name: "Commerce::ProductVariant", foreign_key: :store_product_variant_id, optional: true
    has_many :fulfillments, class_name: "Commerce::Fulfillment", foreign_key: :store_order_item_id, dependent: :destroy

    validates :product_name, presence: true
    validates :unit_price_cents, :total_cents, numericality: { greater_than_or_equal_to: 0 }
    validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  end
end

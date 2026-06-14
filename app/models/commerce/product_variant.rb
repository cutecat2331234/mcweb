module Commerce
  class ProductVariant < ApplicationRecord
    belongs_to :product, class_name: "Commerce::Product", foreign_key: :store_product_id

    validates :name, presence: true
    validates :sku, presence: true, uniqueness: true
    validates :price_cents, numericality: { greater_than_or_equal_to: 0 }

    def in_stock?
      return true if stock.nil?

      stock > 0
    end

    def low_stock?
      return false if stock.nil?

      stock.positive? && stock <= Commerce::SalesMetrics::LOW_STOCK_THRESHOLD
    end

    def price
      price_cents / 100.0
    end
  end
end

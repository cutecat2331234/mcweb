module Commerce
  class Product < ApplicationRecord
    include HasPublicId

    belongs_to :category, class_name: "Commerce::Category", foreign_key: :store_category_id, optional: true
    has_many :variants, class_name: "Commerce::ProductVariant", foreign_key: :store_product_id, dependent: :destroy
    has_many :wishlist_items, class_name: "Commerce::WishlistItem", foreign_key: :store_product_id, dependent: :destroy
    has_many :reviews, class_name: "Commerce::Review", foreign_key: :store_product_id, dependent: :destroy

    enum :status, { draft: "draft", active: "active", archived: "archived" }, validate: true

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: true
    validates :product_type, presence: true
    validates :price_cents, numericality: { greater_than_or_equal_to: 0 }
    validates :currency, presence: true

    scope :available, -> { where(status: :active) }

    def in_stock?
      return true if stock.nil?

      stock > 0
    end

    def price
      price_cents / 100.0
    end
  end
end

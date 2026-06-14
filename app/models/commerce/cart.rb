module Commerce
  class Cart < ApplicationRecord
    belongs_to :user, optional: true
    has_many :items, class_name: "Commerce::CartItem", foreign_key: :store_cart_id, dependent: :destroy

    before_create :generate_session_token, unless: :user_id?

    validates :session_token, uniqueness: true, allow_nil: true

    def add_item!(product:, variant: nil, quantity: 1)
      item = items.find_or_initialize_by(
        store_product_id: product.id,
        store_product_variant_id: variant&.id
      )
      item.quantity = (item.persisted? ? item.quantity : 0) + quantity
      item.save!
      item
    end

    def subtotal_cents
      items.includes(:product, :variant).sum do |item|
        price = item.variant&.price_cents || item.product.price_cents
        price * item.quantity
      end
    end

    def empty?
      items.none?
    end

    private

    def generate_session_token
      self.session_token = SecureRandom.urlsafe_base64(24)
    end
  end
end

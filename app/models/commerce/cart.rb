module Commerce
  class Cart < ApplicationRecord
    belongs_to :user, optional: true
    has_many :items, class_name: "Commerce::CartItem", foreign_key: :store_cart_id, dependent: :destroy

    before_create :generate_session_token, unless: :user_id?
    before_create :ensure_recovery_token

    validates :session_token, uniqueness: true, allow_nil: true
    validates :recovery_token, uniqueness: true, allow_nil: true

    def add_item!(product:, variant: nil, quantity: 1)
      item = items.find_or_initialize_by(
        store_product_id: product.id,
        store_product_variant_id: variant&.id
      )
      item.quantity = (item.persisted? ? item.quantity : 0) + quantity
      item.save!
      reset_abandoned_reminder!
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

    def reset_abandoned_reminder!
      return unless abandoned_reminder_sent_at.present? || abandoned_second_reminder_sent_at.present?

      update_columns(abandoned_reminder_sent_at: nil, abandoned_second_reminder_sent_at: nil)
    end

    def ensure_recovery_token!
      return if recovery_token.present?

      update_column(:recovery_token, generate_recovery_token)
    end

    def recovery_cart_url(coupon: nil)
      ensure_recovery_token!
      options = Rails.application.config.action_mailer.default_url_options.symbolize_keys
      options[:recovery] = recovery_token
      options[:coupon] = coupon if coupon.present?
      options[:host] ||= "localhost"
      Rails.application.routes.url_helpers.store_cart_url(**options)
    end

    private

    def generate_session_token
      self.session_token = SecureRandom.urlsafe_base64(24)
    end

    def ensure_recovery_token
      self.recovery_token ||= generate_recovery_token
    end

    def generate_recovery_token
      loop do
        token = SecureRandom.urlsafe_base64(24)
        break token unless self.class.exists?(recovery_token: token)
      end
    end
  end
end

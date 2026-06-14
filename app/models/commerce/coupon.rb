module Commerce
  class Coupon < ApplicationRecord
    has_many :orders, class_name: "Commerce::Order", foreign_key: :store_coupon_id, dependent: :nullify

    enum :discount_type, { percentage: "percentage", fixed: "fixed" }, validate: true

    validates :code, presence: true, uniqueness: { case_sensitive: false }
    validates :discount_type, presence: true
    validates :discount_value, numericality: { greater_than: 0 }

    scope :active_coupons, -> { where(active: true) }

    def applicable?(subtotal_cents:)
      return false unless active?
      return false if starts_at.present? && starts_at > Time.current
      return false if ends_at.present? && ends_at < Time.current
      return false if usage_limit.present? && used_count >= usage_limit
      return false if subtotal_cents < min_amount_cents

      true
    end

    def calculate_discount(subtotal_cents)
      return 0 unless applicable?(subtotal_cents: subtotal_cents)

      case discount_type
      when "percentage"
        (subtotal_cents * discount_value / 100.0).round
      when "fixed"
        [ discount_value, subtotal_cents ].min
      else
        0
      end
    end

    def redeem!
      increment!(:used_count)
    end
  end
end

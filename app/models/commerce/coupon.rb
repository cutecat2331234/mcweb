module Commerce
  class Coupon < ApplicationRecord
    has_many :orders, class_name: "Commerce::Order", foreign_key: :store_coupon_id, dependent: :nullify

    enum :discount_type, { percentage: "percentage", fixed: "fixed" }, validate: true

    validates :code, presence: true, uniqueness: { case_sensitive: false }
    validates :discount_type, presence: true
    validates :discount_value, numericality: { greater_than: 0 }

    scope :active_coupons, -> { where(active: true) }

    def applicable?(subtotal_cents:, cart_items: nil, user: nil)
      inapplicable_reason(subtotal_cents: subtotal_cents, cart_items: cart_items, user: user).nil?
    end

    def inapplicable_reason(subtotal_cents:, cart_items: nil, user: nil)
      return "优惠券无效或已停用" unless active?
      return "优惠券尚未生效" if starts_at.present? && starts_at > Time.current
      return "优惠券已过期" if ends_at.present? && ends_at < Time.current
      return "优惠券已达使用上限" if usage_limit.present? && used_count >= usage_limit
      return "未达到最低消费金额" if subtotal_cents < min_amount_cents
      return "优惠券不适用于购物车商品" unless matches_cart_restrictions?(cart_items)
      return "仅限首单使用" if first_order_only? && user && !first_order?(user)
      return "已达到每人限用次数" if per_user_limit.present? && user && user_usage_count(user) >= per_user_limit

      nil
    end

    def calculate_discount(subtotal_cents, cart_items: nil, user: nil)
      return 0 unless applicable?(subtotal_cents: subtotal_cents, cart_items: cart_items, user: user)

      amount = case discount_type
               when "percentage"
                 (subtotal_cents * discount_value / 100.0).round
               when "fixed"
                 [ discount_value, subtotal_cents ].min
               else
                 0
               end

      if max_discount_cents.present? && max_discount_cents.positive?
        amount = [ amount, max_discount_cents ].min
      end

      amount
    end

    def shipping_discount?
      free_shipping?
    end

    def redeem!
      increment!(:used_count)
    end

    def restricted_product_ids
      Array(product_ids).map(&:to_i).reject(&:zero?)
    end

    def restricted_category_ids
      Array(category_ids).map(&:to_i).reject(&:zero?)
    end

    private

    def first_order?(user)
      !Commerce::Order.where(user: user, status: %w[paid processing fulfilling fulfilled completed]).exists?
    end

    def user_usage_count(user)
      Commerce::Order.where(user: user, store_coupon_id: id).where.not(status: %w[pending cancelled failed]).count
    end

    def matches_cart_restrictions?(cart_items)
      product_ids = restricted_product_ids
      category_ids = restricted_category_ids
      return true if product_ids.empty? && category_ids.empty?
      return false if cart_items.blank?

      item_product_ids = cart_items.map { |item| item.product.id }
      item_category_ids = cart_items.filter_map { |item| item.product.store_category_id }

      product_match = product_ids.empty? || (product_ids & item_product_ids).any?
      category_match = category_ids.empty? || (category_ids & item_category_ids).any?

      product_match && category_match
    end
  end
end

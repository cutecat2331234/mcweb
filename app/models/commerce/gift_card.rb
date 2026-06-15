# frozen_string_literal: true

module Commerce
  class GiftCard < ApplicationRecord
    self.table_name = "store_gift_cards"

    belongs_to :created_by, class_name: "User", optional: true
    belongs_to :owner_user, class_name: "User", optional: true
    belongs_to :source_order_item, class_name: "Commerce::OrderItem", foreign_key: :source_order_item_id, optional: true
    has_many :transactions, class_name: "Commerce::GiftCardTransaction", foreign_key: :store_gift_card_id, dependent: :destroy
    has_many :orders, class_name: "Commerce::Order", foreign_key: :store_gift_card_id, dependent: :nullify

    validates :code, presence: true, uniqueness: { case_sensitive: false }
    validates :balance_cents, :initial_balance_cents, numericality: { greater_than_or_equal_to: 0 }
    validates :currency, presence: true

    before_validation :normalize_code

    scope :active_cards, -> { where(active: true) }

    def expired?
      expires_at.present? && expires_at < Time.current
    end

    def redeemable?
      active? && balance_cents.positive? && !expired?
    end

    def inapplicable_reason
      return "礼品卡无效或已停用" unless active?
      return "礼品卡已过期" if expired?
      return "礼品卡余额不足" unless balance_cents.positive?

      nil
    end

    def applicable_amount_cents(order_total_cents, excluding_order: nil)
      available = available_balance_cents(excluding_order: excluding_order)
      [ available, order_total_cents ].min
    end

    def available_balance_cents(excluding_order: nil)
      balance_cents - pending_reserved_cents(excluding_order: excluding_order)
    end

    def pending_reserved_cents(excluding_order: nil)
      scope = orders.where(status: "pending")
      scope = scope.where.not(id: excluding_order.id) if excluding_order&.persisted?
      scope.sum(:gift_card_amount_cents)
    end

    private

    def normalize_code
      self.code = code.to_s.strip.upcase if code.present?
    end
  end
end

# frozen_string_literal: true

module Commerce
  class GiftCard < ApplicationRecord
    self.table_name = "store_gift_cards"

    belongs_to :created_by, class_name: "User", optional: true
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

    def applicable_amount_cents(order_total_cents)
      [ balance_cents, order_total_cents ].min
    end

    private

    def normalize_code
      self.code = code.to_s.strip.upcase if code.present?
    end
  end
end

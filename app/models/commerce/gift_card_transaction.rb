# frozen_string_literal: true

module Commerce
  class GiftCardTransaction < ApplicationRecord
    self.table_name = "store_gift_card_transactions"

    belongs_to :gift_card, class_name: "Commerce::GiftCard", foreign_key: :store_gift_card_id
    belongs_to :order, class_name: "Commerce::Order", foreign_key: :store_order_id, optional: true

    TYPES = %w[debit credit].freeze

    validates :transaction_type, inclusion: { in: TYPES }
    validates :amount_cents, numericality: { other_than: 0 }
    validates :balance_after_cents, numericality: { greater_than_or_equal_to: 0 }
  end
end

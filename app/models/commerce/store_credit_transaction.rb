# frozen_string_literal: true

module Commerce
  class StoreCreditTransaction < ApplicationRecord
    self.table_name = "store_credit_transactions"

    belongs_to :user
    belongs_to :order, class_name: "Commerce::Order", foreign_key: :store_order_id, optional: true
    belongs_to :actor, class_name: "User", optional: true

    validates :amount_cents, presence: true, numericality: { other_than: 0 }

    scope :recent, -> { order(created_at: :desc) }
  end
end

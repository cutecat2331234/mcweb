# frozen_string_literal: true

module Community
  class PointTransaction < ApplicationRecord
    self.table_name = "forum_point_transactions"

    belongs_to :account,
               class_name: "Community::PointAccount",
               foreign_key: :forum_point_account_id
    belongs_to :user
    belongs_to :source, polymorphic: true, optional: true

    validates :currency, presence: true
    validates :reason, presence: true
    validates :amount, numericality: { only_integer: true }
    validates :balance_after, numericality: { only_integer: true }
  end
end

# frozen_string_literal: true

module Community
  class PointAccount < ApplicationRecord
    self.table_name = "forum_point_accounts"

    belongs_to :user
    has_many :transactions,
             class_name: "Community::PointTransaction",
             foreign_key: :forum_point_account_id,
             dependent: :destroy

    validates :currency, presence: true
    validates :balance, numericality: { only_integer: true }
    validates :user_id, uniqueness: { scope: :currency }
  end
end

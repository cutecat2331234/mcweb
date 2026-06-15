# frozen_string_literal: true

module Commerce
  class OrderStaffNote < ApplicationRecord
    belongs_to :order, class_name: "Commerce::Order", foreign_key: :store_order_id
    belongs_to :author, class_name: "User"

    validates :body, presence: true

    scope :recent, -> { order(created_at: :desc) }
  end
end

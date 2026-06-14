# frozen_string_literal: true

module Commerce
  class ProductView < ApplicationRecord
    belongs_to :user
    belongs_to :product, class_name: "Commerce::Product", foreign_key: :store_product_id

    validates :user_id, uniqueness: { scope: :store_product_id }

    scope :recent_for, ->(user) { where(user: user).order(viewed_at: :desc) }
  end
end

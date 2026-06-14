# frozen_string_literal: true

module Commerce
  class Review < ApplicationRecord
    belongs_to :user
    belongs_to :product, class_name: "Commerce::Product", foreign_key: :store_product_id

    enum :status, { published: "published", hidden: "hidden" }, validate: true

    validates :rating, presence: true, inclusion: { in: 1..5 }
    validates :user_id, uniqueness: { scope: :store_product_id }
  end
end

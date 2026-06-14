# frozen_string_literal: true

module Commerce
  class Review < ApplicationRecord
    belongs_to :user
    belongs_to :product, class_name: "Commerce::Product", foreign_key: :store_product_id
    has_many :helpful_votes, class_name: "Commerce::ReviewHelpfulVote", foreign_key: :store_review_id, dependent: :destroy

    enum :status, { published: "published", hidden: "hidden" }, validate: true

    validates :rating, presence: true, inclusion: { in: 1..5 }
    validates :user_id, uniqueness: { scope: :store_product_id }
  end
end

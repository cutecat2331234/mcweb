# frozen_string_literal: true

module Commerce
  class ReviewHelpfulVote < ApplicationRecord
    self.table_name = "store_review_helpful_votes"

    belongs_to :review, class_name: "Commerce::Review", foreign_key: :store_review_id
    belongs_to :user

    validates :user_id, uniqueness: { scope: :store_review_id }
  end
end

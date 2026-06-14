# frozen_string_literal: true

module Commerce
  class AnswerHelpfulVote < ApplicationRecord
    self.table_name = "store_product_answer_helpful_votes"

    belongs_to :answer, class_name: "Commerce::ProductAnswer", foreign_key: :store_product_answer_id
    belongs_to :user

    validates :user_id, uniqueness: { scope: :store_product_answer_id }
  end
end

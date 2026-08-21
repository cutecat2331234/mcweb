# frozen_string_literal: true

module Commerce
  class ProductAnswer < ApplicationRecord
    belongs_to :question, class_name: "Commerce::ProductQuestion", foreign_key: :store_product_question_id
    belongs_to :user
    has_many :helpful_votes, class_name: "Commerce::AnswerHelpfulVote", foreign_key: :store_product_answer_id, dependent: :destroy

    enum :status, { published: "published", hidden: "hidden", deleted: "deleted" }, validate: true

    validates :body, presence: true, length: { maximum: 2_000 }

    scope :visible, -> { published }
  end
end

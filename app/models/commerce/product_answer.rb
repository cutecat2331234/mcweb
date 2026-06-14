# frozen_string_literal: true

module Commerce
  class ProductAnswer < ApplicationRecord
    belongs_to :question, class_name: "Commerce::ProductQuestion", foreign_key: :store_product_question_id
    belongs_to :user

    validates :body, presence: true
  end
end

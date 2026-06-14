# frozen_string_literal: true

module Commerce
  class ProductQuestion < ApplicationRecord
    belongs_to :user
    belongs_to :product, class_name: "Commerce::Product", foreign_key: :store_product_id
    has_many :answers, class_name: "Commerce::ProductAnswer", foreign_key: :store_product_question_id, dependent: :destroy

    enum :status, { published: "published", hidden: "hidden" }, validate: true

    validates :body, presence: true

    scope :visible, -> { where(status: :published) }
    scope :recent, -> { order(created_at: :desc) }
  end
end

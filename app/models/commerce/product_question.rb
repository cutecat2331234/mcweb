# frozen_string_literal: true

module Commerce
  class ProductQuestion < ApplicationRecord
    belongs_to :user
    belongs_to :product, class_name: "Commerce::Product", foreign_key: :store_product_id
    belongs_to :order_item, class_name: "Commerce::OrderItem", foreign_key: :store_order_item_id, optional: true
    has_many :answers, class_name: "Commerce::ProductAnswer", foreign_key: :store_product_question_id, dependent: :destroy
    has_many :visible_answers, -> { published }, class_name: "Commerce::ProductAnswer",
      foreign_key: :store_product_question_id

    enum :status, { published: "published", hidden: "hidden", deleted: "deleted" }, validate: true

    validates :body, presence: true, length: { maximum: 2_000 }

    scope :visible, -> { where(status: :published) }
    scope :recent, -> { order(created_at: :desc) }
  end
end

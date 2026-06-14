module Commerce
  class Category < ApplicationRecord
    has_many :products, class_name: "Commerce::Product", foreign_key: :store_category_id, dependent: :nullify

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: true

    scope :ordered, -> { order(:position) }
  end
end

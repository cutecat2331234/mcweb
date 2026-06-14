module Community
  class Category < ApplicationRecord
    has_many :sections, class_name: "Community::Section", foreign_key: :forum_category_id, dependent: :destroy

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: true

    scope :ordered, -> { order(:position) }
  end
end

module Website
  class Block < ApplicationRecord
    belongs_to :page, class_name: "Website::Page", foreign_key: :website_page_id

    validates :block_type, presence: true
    validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    scope :visible_blocks, -> { where(visible: true) }
    scope :ordered, -> { order(:position) }

    default_scope { ordered }
  end
end

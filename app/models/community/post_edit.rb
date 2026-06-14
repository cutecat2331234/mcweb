module Community
  class PostEdit < ApplicationRecord
    belongs_to :post, class_name: "Community::Post", foreign_key: :forum_post_id
    belongs_to :editor, class_name: "User"

    validates :body_after, presence: true

    scope :recent, -> { order(created_at: :desc) }
  end
end

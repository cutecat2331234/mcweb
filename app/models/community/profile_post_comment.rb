# frozen_string_literal: true

module Community
  # A comment on a profile-wall post.
  class ProfilePostComment < ApplicationRecord
    include SoftDeletable

    belongs_to :profile_post, class_name: "Community::ProfilePost", inverse_of: :comments
    belongs_to :author, class_name: "User", foreign_key: :user_id, inverse_of: false

    enum :status, { published: "published", hidden: "hidden" }, validate: true

    validates :body, presence: true, length: { maximum: 3000 }

    scope :chronological, -> { order(created_at: :asc) }
    scope :visible, -> { published }
  end
end

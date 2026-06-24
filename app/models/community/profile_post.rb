# frozen_string_literal: true

module Community
  # A post written on a user's profile wall (XenForo-style profile posts).
  class ProfilePost < ApplicationRecord
    include SoftDeletable

    belongs_to :profile_user, class_name: "User"
    belongs_to :author, class_name: "User", foreign_key: :user_id, inverse_of: false
    has_many :comments, class_name: "Community::ProfilePostComment",
             foreign_key: :profile_post_id, dependent: :destroy, inverse_of: :profile_post

    enum :status, { published: "published", hidden: "hidden" }, validate: true

    validates :body, presence: true, length: { maximum: 5000 }

    scope :recent, -> { order(created_at: :desc) }
    scope :visible, -> { published }
  end
end

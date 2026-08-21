# frozen_string_literal: true

module Commerce
  class Review < ApplicationRecord
    belongs_to :user
    belongs_to :product, class_name: "Commerce::Product", foreign_key: :store_product_id
    belongs_to :forum_post, class_name: "Community::Post", foreign_key: :forum_post_id, optional: true
    has_many :helpful_votes, class_name: "Commerce::ReviewHelpfulVote", foreign_key: :store_review_id, dependent: :destroy
    has_many_attached :photos

    enum :status, { published: "published", hidden: "hidden", deleted: "deleted" }, validate: true
    after_commit -> { Website::HomeCache.bump! }

    validates :rating, presence: true, inclusion: { in: 1..5 }
    validates :body, length: { maximum: 5_000 }, allow_blank: true
    validates :user_id, uniqueness: { scope: :store_product_id }
    validate :photos_limit

    scope :visible, -> { published }

    private

    def photos_limit
      return unless photos.attached? && photos.count > 3

      errors.add(:photos, I18n.t("mcweb.validation_errors.cannot_exceed_3_images"))
    end
  end
end

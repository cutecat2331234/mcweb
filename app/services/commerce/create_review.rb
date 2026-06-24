# frozen_string_literal: true

module Commerce
  class CreateReview < ApplicationService
    def initialize(user:, product:, rating:, body: nil, photos: nil)
      @user = user
      @product = product
      @rating = rating.to_i
      @body = body&.strip
      @photos = photos
    end

    def call
      return ServiceResult.failure(error: "review_rating_invalid") unless (1..5).cover?(@rating)
      return ServiceResult.failure(error: "purchase_required_to_review") unless purchased?

      review = Commerce::Review.find_or_initialize_by(user: @user, product: @product)
      # Don't let a resubmit silently un-hide a review that a moderator (or the user) hid:
      # there is exactly one review row per (user, product), so forcing :published would
      # resurrect moderated/deleted content. Preserve a hidden status on resubmit.
      new_status = review.persisted? && review.hidden? ? :hidden : :published
      review.assign_attributes(rating: @rating, body: @body, status: new_status)
      review.save!
      attach_photos!(review)

      ServiceResult.success(review)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def self.purchased?(user:, product:)
      Commerce::OrderItem
        .joins(:order)
        .where(store_orders: { user_id: user.id, status: %w[paid processing fulfilling fulfilled completed] })
        .exists?(store_product_id: product.id)
    end

    def purchased?
      self.class.purchased?(user: @user, product: @product)
    end

    def attach_photos!(review)
      photos = Array(@photos).select { |photo| photo.respond_to?(:content_type) }
      return if photos.blank?

      review.photos.purge if review.photos.attached?

      photos.first(3).each do |photo|
        next unless %w[image/jpeg image/png image/gif image/webp].include?(photo.content_type)
        next if photo.size > 2.megabytes

        review.photos.attach(photo)
      end
    end
  end
end

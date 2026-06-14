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
      return ServiceResult.failure(error: "Rating must be between 1 and 5.") unless (1..5).cover?(@rating)
      return ServiceResult.failure(error: "Purchase required to review.") unless purchased?

      review = Commerce::Review.find_or_initialize_by(user: @user, product: @product)
      review.assign_attributes(rating: @rating, body: @body, status: :published)
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
      return if @photos.blank?

      Array(@photos).first(3).each do |photo|
        next unless photo.respond_to?(:content_type)
        next unless %w[image/jpeg image/png image/gif image/webp].include?(photo.content_type)
        next if photo.size > 2.megabytes

        review.photos.attach(photo)
      end
    end
  end
end

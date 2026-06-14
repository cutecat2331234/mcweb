# frozen_string_literal: true

module Commerce
  class CreateReview < ApplicationService
    def initialize(user:, product:, rating:, body: nil)
      @user = user
      @product = product
      @rating = rating.to_i
      @body = body&.strip
    end

    def call
      return ServiceResult.failure(error: "Rating must be between 1 and 5.") unless (1..5).cover?(@rating)
      return ServiceResult.failure(error: "Purchase required to review.") unless purchased?

      review = Commerce::Review.find_or_initialize_by(user: @user, product: @product)
      review.assign_attributes(rating: @rating, body: @body, status: :published)
      review.save!

      ServiceResult.success(review)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def purchased?
      Commerce::OrderItem
        .joins(:order)
        .where(store_orders: { user_id: @user.id, status: %w[paid fulfilled] })
        .exists?(store_product_id: @product.id)
    end
  end
end

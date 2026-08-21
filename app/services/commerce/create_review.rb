# frozen_string_literal: true

module Commerce
  class CreateReview < ApplicationService
    def initialize(user:, product:, rating:, body: nil, photos: nil)
      @user = user
      @product = product
      @rating = rating.to_i
      @body = body&.strip
      @photos = Commerce::ReviewPhotoValidator.files(photos)
    end

    def call
      return ServiceResult.failure(error: :review_rating_invalid) unless (1..5).cover?(@rating)
      return ServiceResult.failure(error: :purchase_required_to_review) unless purchased?
      return ServiceResult.failure(error: :review_body_too_long) if @body.to_s.length > 5_000
      if (photo_error = Commerce::ReviewPhotoValidator.validate(@photos))
        return ServiceResult.failure(error: photo_error)
      end

      review = nil
      failure_error = nil
      republished = false
      stale_blobs = []

      Commerce::Review.transaction do
        review = Commerce::Review.lock.find_by(user: @user, product: @product)
        if review&.hidden?
          failure_error = :review_hidden_by_moderator
          raise ActiveRecord::Rollback
        elsif review&.published?
          failure_error = :review_already_exists
          raise ActiveRecord::Rollback
        end

        republished = review&.deleted? || false
        review ||= Commerce::Review.new(user: @user, product: @product)
        previous_state = if review.persisted?
          review.attributes.slice("rating", "status", "deleted_at").merge(
            Commerce::AuditContentSnapshot.fields("body", review.body)
          )
        else
          {}
        end

        if republished && review.photos.attached?
          old_attachments = review.photos.attachments.includes(:blob).to_a
          stale_blobs = old_attachments.map(&:blob)
          old_attachments.each(&:delete)
        end
        review.update!(rating: @rating, body: @body, status: :published, deleted_at: nil)
        @photos.each { |photo| review.photos.attach(photo) }

        Administration::AuditLogger.call(
          actor: @user,
          action: republished ? "commerce.review_republished" : "commerce.review_created",
          resource: review,
          metadata: { product_public_id: @product.public_id, photo_count: @photos.length },
          before_state: previous_state,
          after_state: review.attributes.slice("rating", "status", "deleted_at").merge(
            Commerce::AuditContentSnapshot.fields("body", review.body)
          )
        )
      end

      return ServiceResult.failure(error: failure_error) if failure_error

      purge_after_commit(stale_blobs)
      ServiceResult.success(review)
    rescue ActiveRecord::RecordNotUnique
      ServiceResult.failure(error: :review_already_exists)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    def self.purchased?(user:, product:)
      Commerce::OrderItem
        .joins(:order)
        .where(store_orders: { user_id: user.id, status: %w[paid processing fulfilling fulfilled completed] })
        .exists?(store_product_id: product.id)
    end

    private

    def purchased?
      self.class.purchased?(user: @user, product: @product)
    end

    def purge_after_commit(blobs)
      return if blobs.empty?

      ActiveRecord.after_all_transactions_commit { blobs.each(&:purge_later) }
    end
  end
end

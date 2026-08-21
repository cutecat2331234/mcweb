# frozen_string_literal: true

module Commerce
  class DeleteReview < ApplicationService
    def initialize(user:, review:)
      @user = user
      @review = review
    end

    def call
      return ServiceResult.failure(error: :delete_review_unauthorized) unless @user.id == @review.user_id

      deleted_review = nil
      failure_error = nil
      idempotent = false

      Commerce::Review.transaction do
        review = Commerce::Review.lock.find(@review.id)
        unless review.user_id == @user.id
          failure_error = :delete_review_unauthorized
          raise ActiveRecord::Rollback
        end
        if review.deleted?
          idempotent = true
          deleted_review = review
          next
        end
        if review.hidden?
          failure_error = :review_hidden_by_moderator
          raise ActiveRecord::Rollback
        end

        review.update!(status: :deleted, deleted_at: Time.current)
        Administration::AuditLogger.call(
          actor: @user,
          action: "commerce.review_deleted",
          resource: review,
          metadata: { product_public_id: review.product.public_id, forum_snapshot_retained: review.forum_post_id.present? },
          before_state: { status: "published" },
          after_state: { status: "deleted", deleted_at: review.deleted_at }
        )
        deleted_review = review
      end

      return ServiceResult.failure(error: failure_error) if failure_error

      ServiceResult.success(review: deleted_review, idempotent: idempotent)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

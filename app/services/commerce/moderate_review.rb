# frozen_string_literal: true

module Commerce
  class ModerateReview < ApplicationService
    TARGET_STATUSES = %w[published hidden].freeze

    def initialize(review:, actor:, target_status:)
      @review = review
      @actor = actor
      @target_status = target_status.to_s
    end

    def call
      return moderation_failure unless TARGET_STATUSES.include?(@target_status)

      moderated_review = nil
      failure_error = nil
      idempotent = false

      Commerce::Review.transaction do
        review = Commerce::Review.lock.find(@review.id)
        if review.deleted?
          failure_error = :review_not_moderatable
          raise ActiveRecord::Rollback
        end

        if review.status == @target_status
          idempotent = true
          moderated_review = review
          next
        end

        unless (review.published? && @target_status == "hidden") ||
            (review.hidden? && @target_status == "published")
          failure_error = :review_not_moderatable
          raise ActiveRecord::Rollback
        end

        previous_status = review.status
        review.update!(status: @target_status)
        Administration::AuditLogger.call(
          actor: @actor,
          action: "commerce.review_moderation_status_changed",
          resource: review,
          before_state: { status: previous_status },
          after_state: { status: review.status }
        )
        moderated_review = review
      end

      return moderation_failure if failure_error

      ServiceResult.success(review: moderated_review, idempotent: idempotent)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def moderation_failure
      ServiceResult.failure(error: :review_not_moderatable, code: :review_not_moderatable)
    end
  end
end

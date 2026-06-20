# frozen_string_literal: true

module Commerce
  class DeleteReview < ApplicationService
    def initialize(user:, review:)
      @user = user
      @review = review
    end

    def call
      return ServiceResult.failure(error: "delete_review_unauthorized") unless @user.id == @review.user_id

      @review.update!(status: :hidden)
      ServiceResult.success
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

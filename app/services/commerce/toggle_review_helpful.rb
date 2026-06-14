# frozen_string_literal: true

module Commerce
  class ToggleReviewHelpful < ApplicationService
    def initialize(user:, review:)
      @user = user
      @review = review
    end

    def call
      return ServiceResult.failure(error: "You cannot vote on your own review.") if @user.id == @review.user_id

      existing = Commerce::ReviewHelpfulVote.find_by(user: @user, review: @review)
      if existing
        existing.destroy!
        ServiceResult.success(helpful: false, count: @review.helpful_votes.count)
      else
        Commerce::ReviewHelpfulVote.create!(user: @user, review: @review)
        ServiceResult.success(helpful: true, count: @review.helpful_votes.count)
      end
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

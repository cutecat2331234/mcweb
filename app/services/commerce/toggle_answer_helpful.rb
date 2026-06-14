# frozen_string_literal: true

module Commerce
  class ToggleAnswerHelpful < ApplicationService
    def initialize(user:, answer:)
      @user = user
      @answer = answer
    end

    def call
      return ServiceResult.failure(error: "不能给自己的回答点有帮助。") if @user.id == @answer.user_id

      existing = Commerce::AnswerHelpfulVote.find_by(user: @user, answer: @answer)
      if existing
        existing.destroy!
        ServiceResult.success(helpful: false, count: @answer.helpful_votes.count)
      else
        Commerce::AnswerHelpfulVote.create!(user: @user, answer: @answer)
        ServiceResult.success(helpful: true, count: @answer.helpful_votes.count)
      end
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

# frozen_string_literal: true

module Commerce
  class AnswerProductQuestion < ApplicationService
    def initialize(user:, question:, body:, official: false)
      @user = user
      @question = question
      @body = body.to_s.strip
      @official = official
    end

    def call
      return ServiceResult.failure(error: :answer_is_required) if @body.blank?
      return ServiceResult.failure(error: :answer_too_long) if @body.length > 2_000
      return ServiceResult.failure(error: :question_not_answerable) unless @question.published?

      answer = Commerce::ProductAnswer.create!(
        question: @question,
        user: @user,
        body: @body,
        official: @official,
        status: :published
      )
      Commerce::NotifyProductQuestionAnswered.call(question: @question, answer: answer)
      ServiceResult.success(answer)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

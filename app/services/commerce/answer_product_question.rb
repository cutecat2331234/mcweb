# frozen_string_literal: true

module Commerce
  class AnswerProductQuestion < ApplicationService
    def initialize(user:, question:, body:)
      @user = user
      @question = question
      @body = body.to_s.strip
    end

    def call
      return ServiceResult.failure(error: :answer_is_required) if @body.blank?
      return ServiceResult.failure(error: :answer_too_long) if @body.length > 2_000

      result = Identity::AuthorizedMutation.with(actor: @user) do |authoritative_actor|
        question = Commerce::ProductQuestion.lock.find(@question.id)
        unless question.published?
          next ServiceResult.failure(
            error: :question_not_answerable,
            code: :question_not_answerable
          )
        end

        answer = Commerce::ProductAnswer.create!(
          question: question,
          user: authoritative_actor,
          body: @body,
          official: official_answer_permission?(authoritative_actor),
          status: :published
        )
        ServiceResult.success(answer)
      end
      return result if result.failure?

      answer = result.value
      Commerce::NotifyProductQuestionAnswered.call(question: @question, answer: answer)
      ServiceResult.success(answer)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def official_answer_permission?(user)
      user.permission?("store.questions.answer") || user.permission?("admin.access")
    end
  end
end

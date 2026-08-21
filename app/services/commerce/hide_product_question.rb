# frozen_string_literal: true

module Commerce
  class HideProductQuestion < ApplicationService
    def initialize(question:, actor: nil)
      @question = question
      @actor = actor
    end

    def call
      changed = false
      hidden_question = nil
      failure_error = nil
      Commerce::ProductQuestion.transaction do
        question = Commerce::ProductQuestion.lock.find(@question.id)
        if question.deleted?
          failure_error = :question_not_moderatable
          raise ActiveRecord::Rollback
        end
        changed = question.published?
        question.update!(status: :hidden) if changed
        if changed
          Administration::AuditLogger.call(
            actor: @actor,
            action: "commerce.product_question_hidden",
            resource: question,
            before_state: { status: "published" },
            after_state: { status: "hidden" }
          )
        end
        hidden_question = question
      end
      return ServiceResult.failure(error: failure_error) if failure_error

      ServiceResult.success(question: hidden_question, idempotent: !changed)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

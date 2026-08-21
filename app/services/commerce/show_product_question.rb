# frozen_string_literal: true

module Commerce
  class ShowProductQuestion < ApplicationService
    def initialize(question:, actor: nil)
      @question = question
      @actor = actor
    end

    def call
      changed = false
      shown_question = nil
      failure_error = nil
      Commerce::ProductQuestion.transaction do
        question = Commerce::ProductQuestion.lock.find(@question.id)
        if question.deleted?
          failure_error = :question_not_moderatable
          raise ActiveRecord::Rollback
        end
        changed = question.hidden?
        question.update!(status: :published) if changed
        if changed
          Administration::AuditLogger.call(
            actor: @actor,
            action: "commerce.product_question_restored",
            resource: question,
            before_state: { status: "hidden" },
            after_state: { status: "published" }
          )
        end
        shown_question = question
      end
      return ServiceResult.failure(error: failure_error) if failure_error

      ServiceResult.success(question: shown_question, idempotent: !changed)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

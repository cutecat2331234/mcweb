# frozen_string_literal: true

module Commerce
  class DeleteProductQuestion < ApplicationService
    def initialize(user:, question:)
      @user = user
      @question = question
    end

    def call
      return ServiceResult.failure(error: :question_delete_unauthorized) unless @question.user_id == @user.id

      deleted_question = nil
      failure_error = nil
      idempotent = false
      Commerce::ProductQuestion.transaction do
        question = Commerce::ProductQuestion.lock.find(@question.id)
        unless question.user_id == @user.id
          failure_error = :question_delete_unauthorized
          raise ActiveRecord::Rollback
        end
        if question.deleted?
          idempotent = true
          deleted_question = question
          next
        end
        if question.hidden?
          failure_error = :question_hidden_by_moderator
          raise ActiveRecord::Rollback
        end

        question.update!(status: :deleted, deleted_at: Time.current)
        Administration::AuditLogger.call(
          actor: @user,
          action: "commerce.product_question_deleted",
          resource: question,
          metadata: { product_public_id: question.product.public_id, retained_answer_count: question.answers.count },
          before_state: { status: "published" },
          after_state: { status: "deleted", deleted_at: question.deleted_at }
        )
        deleted_question = question
      end

      return ServiceResult.failure(error: failure_error) if failure_error

      ServiceResult.success(question: deleted_question, idempotent: idempotent)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

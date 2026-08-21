# frozen_string_literal: true

module Commerce
  class DeleteProductAnswer < ApplicationService
    def initialize(user:, answer:)
      @user = user
      @answer = answer
    end

    def call
      return service_failure(:answer_delete_unauthorized) unless @answer.user_id == @user.id
      deleted_answer = nil
      failure_error = nil
      idempotent = false
      Commerce::ProductAnswer.transaction do
        answer = Commerce::ProductAnswer.lock.find(@answer.id)
        unless answer.user_id == @user.id
          failure_error = :answer_delete_unauthorized
          raise ActiveRecord::Rollback
        end
        authoritative_actor = ::User.lock.find(@user.id) if answer.official?
        if answer.official? && !official_answer_permission?(authoritative_actor)
          failure_error = :official_answer_permission_required
          raise ActiveRecord::Rollback
        end
        if answer.deleted?
          idempotent = true
          deleted_answer = answer
          next
        end
        if answer.hidden?
          failure_error = :answer_hidden_by_moderator
          raise ActiveRecord::Rollback
        end

        answer.update!(status: :deleted, deleted_at: Time.current)
        Administration::AuditLogger.call(
          actor: @user,
          action: "commerce.product_answer_deleted",
          resource: answer,
          metadata: { product_public_id: answer.question.product.public_id, official: answer.official? },
          before_state: { status: "published" },
          after_state: { status: "deleted", deleted_at: answer.deleted_at }
        )
        deleted_answer = answer
      end

      return service_failure(failure_error) if failure_error

      ServiceResult.success(answer: deleted_answer, idempotent: idempotent)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def service_failure(code)
      ServiceResult.failure(error: code, code: code)
    end

    def official_answer_permission?(user)
      user.permission?("store.questions.answer") || user.permission?("admin.access")
    end
  end
end

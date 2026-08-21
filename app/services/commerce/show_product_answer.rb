# frozen_string_literal: true

module Commerce
  class ShowProductAnswer < ApplicationService
    def initialize(answer:, actor: nil)
      @answer = answer
      @actor = actor
    end

    def call
      changed = false
      shown_answer = nil
      failure_error = nil
      Commerce::ProductAnswer.transaction do
        answer = Commerce::ProductAnswer.lock.find(@answer.id)
        if answer.deleted?
          failure_error = :answer_not_moderatable
          raise ActiveRecord::Rollback
        end
        changed = answer.hidden?
        answer.update!(status: :published) if changed
        if changed
          Administration::AuditLogger.call(
            actor: @actor,
            action: "commerce.product_answer_restored",
            resource: answer,
            before_state: { status: "hidden" },
            after_state: { status: "published" }
          )
        end
        shown_answer = answer
      end
      return ServiceResult.failure(error: failure_error) if failure_error

      ServiceResult.success(answer: shown_answer, idempotent: !changed)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

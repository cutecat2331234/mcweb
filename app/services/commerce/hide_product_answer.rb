# frozen_string_literal: true

module Commerce
  class HideProductAnswer < ApplicationService
    def initialize(answer:, actor: nil)
      @answer = answer
      @actor = actor
    end

    def call
      changed = false
      hidden_answer = nil
      failure_error = nil
      Commerce::ProductAnswer.transaction do
        answer = Commerce::ProductAnswer.lock.find(@answer.id)
        if answer.deleted?
          failure_error = :answer_not_moderatable
          raise ActiveRecord::Rollback
        end
        changed = answer.published?
        answer.update!(status: :hidden) if changed
        if changed
          Administration::AuditLogger.call(
            actor: @actor,
            action: "commerce.product_answer_hidden",
            resource: answer,
            before_state: { status: "published" },
            after_state: { status: "hidden" }
          )
        end
        hidden_answer = answer
      end
      return ServiceResult.failure(error: failure_error) if failure_error

      ServiceResult.success(answer: hidden_answer, idempotent: !changed)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

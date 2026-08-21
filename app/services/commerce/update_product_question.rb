# frozen_string_literal: true

module Commerce
  class UpdateProductQuestion < ApplicationService
    def initialize(user:, question:, body:)
      @user = user
      @question = question
      @body = body.to_s.strip
    end

    def call
      return ServiceResult.failure(error: :question_update_unauthorized) unless @question.user_id == @user.id
      return ServiceResult.failure(error: :question_is_required) if @body.blank?
      return ServiceResult.failure(error: :question_too_long) if @body.length > 2_000

      updated_question = nil
      failure_error = nil
      Commerce::ProductQuestion.transaction do
        question = Commerce::ProductQuestion.lock.find(@question.id)
        unless question.user_id == @user.id
          failure_error = :question_update_unauthorized
          raise ActiveRecord::Rollback
        end
        unless question.published?
          failure_error = question.hidden? ? :question_hidden_by_moderator : :question_not_editable
          raise ActiveRecord::Rollback
        end

        before_body = question.body
        question.update!(body: @body, edited_at: Time.current)
        Administration::AuditLogger.call(
          actor: @user,
          action: "commerce.product_question_updated",
          resource: question,
          metadata: { product_public_id: question.product.public_id, changed_fields: [ "body" ] },
          before_state: { status: "published" }.merge(
            Commerce::AuditContentSnapshot.fields("body", before_body)
          ),
          after_state: { status: question.status, edited_at: question.edited_at }.merge(
            Commerce::AuditContentSnapshot.fields("body", question.body)
          )
        )
        updated_question = question
      end

      return ServiceResult.failure(error: failure_error) if failure_error

      ServiceResult.success(updated_question)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

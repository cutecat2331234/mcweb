# frozen_string_literal: true

module Commerce
  class UpdateProductAnswer < ApplicationService
    def initialize(user:, answer:, body:)
      @user = user
      @answer = answer
      @body = body.to_s.strip
    end

    def call
      return ServiceResult.failure(error: :answer_update_unauthorized) unless @answer.user_id == @user.id
      return ServiceResult.failure(error: :answer_is_required) if @body.blank?
      return ServiceResult.failure(error: :answer_too_long) if @body.length > 2_000
      if @answer.official? && !official_answer_permission?
        return ServiceResult.failure(error: :official_answer_permission_required)
      end

      updated_answer = nil
      failure_error = nil
      Commerce::ProductAnswer.transaction do
        answer = Commerce::ProductAnswer.lock.find(@answer.id)
        unless answer.user_id == @user.id
          failure_error = :answer_update_unauthorized
          raise ActiveRecord::Rollback
        end
        unless answer.published? && answer.question.published?
          failure_error = answer.hidden? ? :answer_hidden_by_moderator : :answer_not_editable
          raise ActiveRecord::Rollback
        end
        if answer.official? && !official_answer_permission?
          failure_error = :official_answer_permission_required
          raise ActiveRecord::Rollback
        end

        before_body = answer.body
        answer.update!(body: @body, edited_at: Time.current)
        Administration::AuditLogger.call(
          actor: @user,
          action: "commerce.product_answer_updated",
          resource: answer,
          metadata: {
            product_public_id: answer.question.product.public_id,
            official: answer.official?,
            changed_fields: [ "body" ]
          },
          before_state: { status: "published" }.merge(
            Commerce::AuditContentSnapshot.fields("body", before_body)
          ),
          after_state: { status: answer.status, edited_at: answer.edited_at }.merge(
            Commerce::AuditContentSnapshot.fields("body", answer.body)
          )
        )
        updated_answer = answer
      end

      return ServiceResult.failure(error: failure_error) if failure_error

      ServiceResult.success(updated_answer)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def official_answer_permission?
      @user.permission?("store.questions.answer") || @user.permission?("admin.access")
    end
  end
end

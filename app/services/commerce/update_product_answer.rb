# frozen_string_literal: true

module Commerce
  class UpdateProductAnswer < ApplicationService
    def initialize(user:, answer:, body:, expected_version: nil)
      @user = user
      @answer = answer
      @body = body.to_s.strip
      @expected_version = Integer(expected_version, exception: false)
      @expected_version = nil if @expected_version&.negative?
    end

    def call
      return service_failure(:answer_update_unauthorized) unless @answer.user_id == @user.id
      return service_failure(:answer_revision_required) unless @expected_version
      return service_failure(:answer_is_required) if @body.blank?
      return service_failure(:answer_too_long) if @body.length > 2_000
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
        unless answer.lock_version == @expected_version
          failure_error = :answer_update_conflict
          raise ActiveRecord::Rollback
        end
        authoritative_actor = ::User.lock.find(@user.id) if answer.official?
        if answer.official? && !official_answer_permission?(authoritative_actor)
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

      return service_failure(failure_error) if failure_error

      ServiceResult.success(updated_answer)
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

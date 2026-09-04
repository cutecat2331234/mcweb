# frozen_string_literal: true

module Community
  # Lets the author edit their own conversation message (XenForo/Discourse allow
  # editing your own PMs). Records edited_at so the UI can show an "edited" marker.
  class EditMessage < ApplicationService
    MAX_LENGTH = 10_000

    def initialize(user:, message:, body:, expected_revision: nil)
      @user = user
      @message = message
      @body = body.to_s.strip
      @expected_revision = Integer(expected_revision, exception: false)
    end

    def call
      return ServiceResult.failure(error: "message_edit_unauthorized") unless authorized?
      return ServiceResult.failure(error: "message_deleted") if @message.deleted?
      return ServiceResult.failure(error: "message_body_required") if @body.blank?
      return ServiceResult.failure(error: "message_too_long") if @body.length > MAX_LENGTH
      unless @expected_revision&.positive?
        return ServiceResult.failure(
          error: "message_revision_required",
          code: "message_revision_required"
        )
      end

      result = nil
      Community::Message.transaction do
        @user = User.lock.find_by(id: @user.id)
        unless @user
          result = ServiceResult.failure(error: "message_edit_unauthorized")
          raise ActiveRecord::Rollback
        end
        if @user.deleted? || @user.banned?
          result = ServiceResult.failure(
            error: @user.deleted? ? :account_deleted : :account_banned
          )
          raise ActiveRecord::Rollback
        end

        @message = Community::Message.with_discarded.lock.find_by(id: @message.id)
        unless authorized?
          result = ServiceResult.failure(error: "message_edit_unauthorized")
          raise ActiveRecord::Rollback
        end
        if @message.deleted?
          result = ServiceResult.failure(error: "message_deleted")
          raise ActiveRecord::Rollback
        end
        if @message.revision != @expected_revision
          result = ServiceResult.failure(error: "message_revision_conflict", code: "message_revision_conflict")
          raise ActiveRecord::Rollback
        end

        ensure_initial_revision!
        next_revision = @message.revision + 1
        @message.update!(body: @body, edited_at: Time.current, revision: next_revision)
        @message.revisions.create!(
          editor: @user,
          revision: next_revision,
          body: @body,
          content_digest: Digest::SHA256.hexdigest(@body)
        )
        result = ServiceResult.success(@message)
      end
      result
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def authorized?
      @user&.persisted? &&
        @message.is_a?(Community::Message) &&
        @message.persisted? &&
        @message.user_id == @user.id
    end

    def ensure_initial_revision!
      return if @message.revisions.exists?(revision: @message.revision)

      @message.revisions.create!(
        editor: @message.user,
        revision: @message.revision,
        body: @message.body,
        content_digest: Digest::SHA256.hexdigest(@message.body)
      )
    end
  end
end

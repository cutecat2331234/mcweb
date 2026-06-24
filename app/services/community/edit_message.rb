# frozen_string_literal: true

module Community
  # Lets the author edit their own conversation message (XenForo/Discourse allow
  # editing your own PMs). Records edited_at so the UI can show an "edited" marker.
  class EditMessage < ApplicationService
    MAX_LENGTH = 10_000

    def initialize(user:, message:, body:)
      @user = user
      @message = message
      @body = body.to_s.strip
    end

    def call
      return ServiceResult.failure(error: "message_edit_unauthorized") unless @message.user_id == @user.id
      return ServiceResult.failure(error: "message_body_required") if @body.blank?
      return ServiceResult.failure(error: "message_too_long") if @body.length > MAX_LENGTH

      @message.update!(body: @body, edited_at: Time.current)
      ServiceResult.success(@message)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

# frozen_string_literal: true

module Community
  class SaveMessageDraft < ApplicationService
    def initialize(user:, conversation:, body:, attachment_ids: [])
      @user = user
      @conversation = conversation
      @body = body.to_s
      @raw_attachment_ids = Array(attachment_ids)
      @attachment_ids = @raw_attachment_ids.filter_map { |id| Integer(id, exception: false) }.uniq
    end

    def call
      unless @conversation.participant?(@user)
        return ServiceResult.failure(error: :conversation_not_available)
      end

      if @attachment_ids.size != @raw_attachment_ids.size || @attachment_ids.size > 10
        return ServiceResult.failure(error: "attachment_invalid", code: "attachment_invalid")
      end
      unless valid_attachments?
        return ServiceResult.failure(
          error: "attachment_invalid_or_unauthorized",
          code: "attachment_invalid_or_unauthorized"
        )
      end

      if @body.strip.blank? && @attachment_ids.empty?
        Community::MessageDraft.where(user: @user, conversation: @conversation).delete_all
        return ServiceResult.success(nil)
      end

      draft = Community::MessageDraft.find_or_initialize_by(user: @user, conversation: @conversation)
      draft.body = @body
      draft.attachment_ids = @attachment_ids
      draft.save!
      ServiceResult.success(draft)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def valid_attachments?
      return true if @attachment_ids.empty?

      attachments = Community::PostAttachment
        .unlinked
        .where(user: @user, id: @attachment_ids)
        .includes(:upload_record)
        .to_a
      attachments.size == @attachment_ids.size && attachments.all?(&:scan_bindable?)
    end
  end
end

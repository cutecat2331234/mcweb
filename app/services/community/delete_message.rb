# frozen_string_literal: true

module Community
  class DeleteMessage < ApplicationService
    def initialize(user:, message:)
      @user = user
      @message = message
    end

    def call
      return ServiceResult.failure(error: "message_delete_unauthorized") unless authorized?
      return ServiceResult.success(@message) if @message.deleted?

      @message.soft_delete!
      ServiceResult.success(@message)
    rescue ActiveRecord::ActiveRecordError => e
      ServiceResult.failure(error: e.message)
    end

    private

    def authorized?
      @user&.persisted? &&
        @message.is_a?(Community::Message) &&
        @message.persisted? &&
        (@message.user_id == @user.id || @user.permission?("forum.topics.lock"))
    end
  end
end

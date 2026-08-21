# frozen_string_literal: true

module Community
  class DeleteMessage < ApplicationService
    def initialize(user:, message:, request_id: nil)
      @user = user
      @message = message
      @request_id = request_id
    end

    def call
      return ServiceResult.failure(error: "message_delete_unauthorized") unless authorized?

      result = DataGovernance::SoftDeleteContent.call(
        target: @message,
        actor: @user,
        reason: I18n.t("mcweb.forum.messages.author_delete_reason"),
        request_id: @request_id
      )
      return result if result.failure?

      ServiceResult.success(
        message: @message,
        lifecycle: result.value.fetch(:record),
        replayed: result.value.fetch(:replayed)
      )
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

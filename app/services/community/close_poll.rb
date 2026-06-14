# frozen_string_literal: true

module Community
  class ClosePoll < ApplicationService
    def initialize(user:, poll:)
      @user = user
      @poll = poll
    end

    def call
      topic = @poll.topic
      unless @user.id == topic.user_id || @user.permission?("forum.topics.lock")
        return ServiceResult.failure(error: "Not allowed to close poll.")
      end

      return ServiceResult.failure(error: "Poll is already closed.") unless @poll.open?

      @poll.update!(closes_at: Time.current)
      ServiceResult.success(@poll)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

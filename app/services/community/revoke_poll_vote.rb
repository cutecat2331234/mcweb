# frozen_string_literal: true

module Community
  class RevokePollVote < ApplicationService
    def initialize(user:, poll:)
      @user = user
      @poll = poll
    end

    def call
      return ServiceResult.failure(error: "You are not allowed to vote in this topic.") unless PollParticipation.allowed?(user: @user, poll: @poll)
      return ServiceResult.failure(error: "Poll is closed.") unless @poll.open?

      removed = @poll.votes.where(user: @user).destroy_all.size
      return ServiceResult.failure(error: "You have not voted.") if removed.zero?

      ServiceResult.success
    end
  end
end

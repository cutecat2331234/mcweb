# frozen_string_literal: true

module Community
  class RevokePollVote < ApplicationService
    def initialize(user:, poll:)
      @user = user
      @poll = poll
    end

    def call
      return ServiceResult.failure(error: :cannot_vote_in_topic) unless PollParticipation.allowed?(user: @user, poll: @poll)
      return ServiceResult.failure(error: :poll_closed) unless @poll.open?

      removed = @poll.votes.where(user: @user).destroy_all.size
      return ServiceResult.failure(error: :you_have_not_voted) if removed.zero?

      ServiceResult.success
    end
  end
end

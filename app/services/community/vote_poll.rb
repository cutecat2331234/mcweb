# frozen_string_literal: true

module Community
  class VotePoll < ApplicationService
    def initialize(user:, poll:, option_index:)
      @user = user
      @poll = poll
      @option_index = option_index.to_i
    end

    def call
      return ServiceResult.failure(error: "Poll is closed.") unless @poll.open?
      return ServiceResult.failure(error: "Invalid option.") unless @option_index.between?(0, @poll.options.size - 1)

      vote = Community::PollVote.find_or_initialize_by(poll: @poll, user: @user)
      vote.option_index = @option_index
      vote.save!

      ServiceResult.success(vote)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

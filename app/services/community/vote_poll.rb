# frozen_string_literal: true

module Community
  class VotePoll < ApplicationService
    def initialize(user:, poll:, option_index: nil, option_indices: nil)
      @user = user
      @poll = poll
      indices = option_indices.presence || [ option_index ]
      @option_indices = Array(indices).map(&:to_i).uniq.sort
    end

    def call
      return ServiceResult.failure(error: "You are not allowed to vote in this topic.") unless PollParticipation.allowed?(user: @user, poll: @poll)
      return ServiceResult.failure(error: "Poll is closed.") unless @poll.open?
      return ServiceResult.failure(error: "No options selected.") if @option_indices.empty?

      max = @poll.multiple_choice? ? @poll.max_choices : 1
      return ServiceResult.failure(error: "Too many options selected.") if @option_indices.size > max

      invalid = @option_indices.any? { |index| !index.between?(0, @poll.options.size - 1) }
      return ServiceResult.failure(error: "Invalid option.") if invalid

      Community::PollVote.transaction do
        @poll.votes.where(user: @user).destroy_all
        @option_indices.each do |index|
          @poll.votes.create!(user: @user, option_index: index)
        end
      end

      ServiceResult.success(@poll.votes.where(user: @user))
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

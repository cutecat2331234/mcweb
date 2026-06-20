# frozen_string_literal: true

module Community
  class EditTopicPoll < ApplicationService
    NOT_PROVIDED = Object.new

    def initialize(user:, topic:, poll_question: NOT_PROVIDED, poll_options: NOT_PROVIDED, poll_closes_days: nil,
                   poll_multiple_choice: nil, poll_max_choices: nil, poll_hide_results_until_vote: nil,
                   remove_poll: false)
      @user = user
      @topic = topic
      @poll_question_provided = !poll_question.equal?(NOT_PROVIDED)
      @poll_question = @poll_question_provided ? poll_question.to_s.strip.presence : nil
      @poll_options_provided = !poll_options.equal?(NOT_PROVIDED)
      @poll_options = @poll_options_provided ? normalize_options(poll_options) : nil
      @poll_closes_days = poll_closes_days
      @poll_multiple_choice = poll_multiple_choice
      @poll_max_choices = poll_max_choices
      @poll_hide_results_until_vote = poll_hide_results_until_vote
      @remove_poll = remove_poll
    end

    def call
      return ServiceResult.failure(error: "You cannot edit this poll.") unless can_edit?

      poll = @topic.poll
      if @remove_poll || poll_removal_requested?(poll)
        poll&.destroy
        return ServiceResult.success(nil)
      end

      return ServiceResult.failure(error: "Poll not found.") unless poll || @poll_question.present?

      if poll&.votes&.exists? && options_changed?(poll)
        return ServiceResult.failure(error: "Cannot change poll options after votes have been cast.")
      end

      if poll&.votes&.exists? && @poll_question_provided && @poll_question.present? && @poll_question != poll.question
        return ServiceResult.failure(error: "Cannot change poll question after votes have been cast.")
      end

      Community::SyncTopicPoll.call(
        topic: @topic,
        poll_question: @poll_question_provided ? @poll_question : poll&.question,
        poll_options: @poll_options_provided ? @poll_options : poll&.options,
        poll_closes_days: @poll_closes_days.nil? ? existing_closes_days(poll) : @poll_closes_days,
        poll_multiple_choice: @poll_multiple_choice.nil? ? poll&.multiple_choice : @poll_multiple_choice,
        poll_max_choices: @poll_max_choices.nil? ? poll&.max_choices : @poll_max_choices,
        poll_hide_results_until_vote: @poll_hide_results_until_vote.nil? ? poll&.hide_results_until_vote : @poll_hide_results_until_vote
      )
    end

    private

    def can_edit?
      Community::SectionModeration.can_edit_topic?(user: @user, topic: @topic)
    end

    def poll_removal_requested?(poll)
      poll.present? && @poll_question_provided && @poll_question.blank? &&
        @poll_options_provided && @poll_options.blank?
    end

    def normalize_options(raw)
      if raw.is_a?(String)
        raw.lines.map(&:strip).reject(&:blank?)
      else
        Array(raw).map(&:to_s).map(&:strip).reject(&:blank?)
      end
    end

    def options_changed?(poll)
      return false unless @poll_options_provided

      @poll_options != Array(poll.options)
    end

    def existing_closes_days(poll)
      return 0 unless poll&.closes_at

      days = ((poll.closes_at - poll.created_at) / 1.day).round
      days.positive? ? days : 0
    end
  end
end

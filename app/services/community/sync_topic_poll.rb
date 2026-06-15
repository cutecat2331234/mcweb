# frozen_string_literal: true

module Community
  class SyncTopicPoll < ApplicationService
    def initialize(topic:, poll_question: nil, poll_options: nil, poll_closes_days: nil, poll_multiple_choice: nil, poll_max_choices: nil, poll_hide_results_until_vote: nil)
      @topic = topic
      @poll_question = poll_question.to_s.strip.presence
      @poll_options = if poll_options.is_a?(String)
                        poll_options.lines.map(&:strip).reject(&:blank?)
      else
                        Array(poll_options).map(&:to_s).map(&:strip).reject(&:blank?)
      end
      @poll_closes_days = poll_closes_days.to_i
      @poll_multiple_choice = ActiveModel::Type::Boolean.new.cast(poll_multiple_choice) || false
      @poll_max_choices = [ poll_max_choices.to_i, 1 ].max
      @poll_hide_results_until_vote = ActiveModel::Type::Boolean.new.cast(poll_hide_results_until_vote) || false
    end

    def call
      if @poll_question.blank? || @poll_options.size < 2
        @topic.poll&.destroy
        return ServiceResult.success(nil)
      end

      closes_at = @poll_closes_days.positive? ? @poll_closes_days.days.from_now : nil
      max_choices = @poll_multiple_choice ? [ @poll_max_choices, @poll_options.size ].min : 1

      poll = @topic.poll || @topic.build_poll
      poll.assign_attributes(
        question: @poll_question,
        options: @poll_options.first(10),
        closes_at: closes_at,
        multiple_choice: @poll_multiple_choice,
        max_choices: max_choices,
        hide_results_until_vote: @poll_hide_results_until_vote
      )
      poll.save!
      ServiceResult.success(poll)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end

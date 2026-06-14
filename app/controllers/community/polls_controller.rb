# frozen_string_literal: true

module Community
  class PollsController < ApplicationController
    before_action :require_login

    def vote
      poll = Community::Poll.find(params[:id])
      result = Community::VotePoll.call(
        user: current_user,
        poll: poll,
        option_index: params[:option_index],
        option_indices: params[:option_indices]
      )

      if result.success?
        redirect_to forum_topic_path(poll.topic), notice: "投票成功。"
      else
        redirect_to forum_topic_path(poll.topic), alert: service_error_message(result)
      end
    end

    def close
      poll = Community::Poll.find(params[:id])
      result = Community::ClosePoll.call(user: current_user, poll: poll)

      if result.success?
        redirect_to forum_topic_path(poll.topic), notice: "投票已关闭。"
      else
        redirect_to forum_topic_path(poll.topic), alert: service_error_message(result)
      end
    end

    def voters
      poll = Community::Poll.find(params[:id])
      user_votes = poll.votes.where(user: current_user)
      show_results = !poll.hide_results_until_vote || user_votes.exists? || !poll.open?
      return head :forbidden unless show_results || current_user&.permission?("forum.topics.lock")

      voters_by_option = poll.options.each_with_index.map do |label, index|
        usernames = poll.votes.where(option_index: index).includes(:user).map { |v| v.user.username }
        { label: label, index: index, voters: usernames }
      end

      render json: { voters_by_option: voters_by_option }
    end
  end
end

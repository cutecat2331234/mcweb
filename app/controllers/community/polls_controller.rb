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
  end
end

# frozen_string_literal: true

module Community
  class CloseExpiredPollsJob < ApplicationJob
    queue_as :maintenance

    def perform
      Community::Poll
        .where("closes_at IS NOT NULL AND closes_at <= ?", Time.current)
        .includes(:topic)
        .find_each do |poll|
          next unless poll.topic&.status == "published"
          next if poll.updated_at >= poll.closes_at

          actor = Community::SystemActor.user || poll.topic.user
          Community::FinalizePollClosed.call(
            poll: poll,
            actor: actor,
            body: "投票「#{poll.question}」已到期并自动关闭。"
          )
        end
    end
  end
end

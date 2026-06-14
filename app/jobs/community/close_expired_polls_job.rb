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

          poll.touch if poll.updated_at < poll.closes_at
        end
    end
  end
end

# frozen_string_literal: true

module Community
  class BumpScheduledTopicsJob < ApplicationJob
    queue_as :default

    def perform
      Community::Topic
        .where(status: :published)
        .where.not(auto_bump_at: nil)
        .where("auto_bump_at <= ?", Time.current)
        .find_each do |topic|
          Community::BumpScheduledTopic.call(topic: topic)
        end
    end
  end
end

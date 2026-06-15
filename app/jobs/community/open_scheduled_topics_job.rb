# frozen_string_literal: true

module Community
  class OpenScheduledTopicsJob < ApplicationJob
    queue_as :default

    def perform
      Community::Topic.where(status: :published)
        .where.not(auto_open_at: nil)
        .where("auto_open_at <= ?", Time.current)
        .find_each do |topic|
          Community::OpenScheduledTopic.call(topic: topic)
        end
    end
  end
end

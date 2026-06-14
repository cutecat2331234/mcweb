# frozen_string_literal: true

module Community
  class CloseScheduledTopicsJob < ApplicationJob
    queue_as :default

    def perform
      Community::Topic
        .where(status: :published, locked: false)
        .where.not(auto_close_at: nil)
        .where("auto_close_at <= ?", Time.current)
        .find_each do |topic|
          Community::CloseScheduledTopic.call(topic: topic)
        end
    end
  end
end

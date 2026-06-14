# frozen_string_literal: true

module Community
  class PublishScheduledTopicsJob < ApplicationJob
    queue_as :default

    def perform
      Community::Topic
        .where(status: :draft)
        .where.not(scheduled_at: nil)
        .where("scheduled_at <= ?", Time.current)
        .find_each do |topic|
          Community::PublishScheduledTopic.call(topic: topic)
        end
    end
  end
end

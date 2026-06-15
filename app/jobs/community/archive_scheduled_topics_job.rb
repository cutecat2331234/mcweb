# frozen_string_literal: true

module Community
  class ArchiveScheduledTopicsJob < ApplicationJob
    queue_as :default

    def perform
      Community::Topic
        .where(status: :published)
        .where(archived_at: nil)
        .where.not(auto_archive_at: nil)
        .where("auto_archive_at <= ?", Time.current)
        .find_each do |topic|
          Community::ArchiveScheduledTopic.call(topic: topic)
        end
    end
  end
end

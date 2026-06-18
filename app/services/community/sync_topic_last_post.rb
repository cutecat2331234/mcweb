# frozen_string_literal: true

module Community
  class SyncTopicLastPost < ApplicationService
    def initialize(topic:)
      @topic = topic
    end

    def call
      Community::Post.sync_topic_counters!(@topic)
      ServiceResult.success(@topic)
    end
  end
end

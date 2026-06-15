# frozen_string_literal: true

module Community
  class ProcessHashtags < ApplicationService
    HASHTAG_PATTERN = /#([a-zA-Z0-9_\u4e00-\u9fff-]{2,32})/

    def initialize(topic:, body:, user:)
      @topic = topic
      @body = body.to_s
      @user = user
    end

    def call
      names = @body.scan(HASHTAG_PATTERN).flatten.uniq
      return ServiceResult.success(tags: []) if names.empty?

      existing = @topic.tags.pluck(:name)
      merged = (existing + names).uniq.first(Community::SyncTopicTags::MAX_TAGS)
      result = Community::SyncTopicTags.call(topic: @topic, tag_names: merged, user: @user)
      return result if result.failure?

      ServiceResult.success(tags: result.value[:tags], added: names)
    end
  end
end

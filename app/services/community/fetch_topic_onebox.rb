# frozen_string_literal: true

module Community
  class FetchTopicOnebox < ApplicationService
    TOPIC_PATH = %r{\A(?:/app)?/forum/topics/([\w-]+)\z}i

    def initialize(url:)
      @url = url.to_s.strip
    end

    def call
      path = if @url.start_with?("/")
               @url
      else
               URI.parse(@url).path
      end
      return ServiceResult.success(nil) unless path

      match = path.match(TOPIC_PATH)
      return ServiceResult.success(nil) unless match

      topic = Community::Topic.published_listed.find_by(public_id: match[1])
      return ServiceResult.success(nil) unless topic

      ServiceResult.success(
        public_id: topic.public_id,
        title: topic.title,
        author: topic.user&.username,
        replies_count: topic.replies_count,
        section_name: topic.section&.name,
        url: "/app/forum/topics/#{topic.public_id}"
      )
    rescue URI::InvalidURIError
      ServiceResult.success(nil)
    end
  end
end

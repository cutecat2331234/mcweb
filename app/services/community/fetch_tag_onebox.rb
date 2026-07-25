# frozen_string_literal: true

module Community
  class FetchTagOnebox < ApplicationService
    TAG_PATH = %r{\A/forum/tags/([\w-]+)\z}i

    def initialize(url:)
      @url = url.to_s.strip
    end

    def call
      path = @url.start_with?("/") ? @url : URI.parse(@url).path
      match = path.match(TAG_PATH)
      return ServiceResult.success(nil) unless match

      tag = Community::Tag.resolve_by_slug_for(match[1], user: nil)
      return ServiceResult.success(nil) unless tag

      topics_count = Community::ForumAccess.listed_topic_scope(
        relation: tag.topics,
        user: nil
      ).count

      ServiceResult.success(
        slug: tag.slug,
        name: tag.name,
        description: tag.description.to_s.truncate(120),
        topics_count: topics_count,
        url: "#{Mcweb::Paths::APP_PREFIX}/forum/tags/#{tag.slug}"
      )
    rescue URI::InvalidURIError
      ServiceResult.success(nil)
    end
  end
end

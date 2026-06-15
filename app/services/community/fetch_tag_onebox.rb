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

      tag = Community::Tag.resolve_by_slug(match[1])
      return ServiceResult.success(nil) unless tag

      ServiceResult.success(
        slug: tag.slug,
        name: tag.name,
        description: tag.description.to_s.truncate(120),
        topics_count: tag.topics.where(status: :published).count,
        url: "/forum/tags/#{tag.slug}"
      )
    rescue URI::InvalidURIError
      ServiceResult.success(nil)
    end
  end
end

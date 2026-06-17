# frozen_string_literal: true

module Community
  class FetchSectionOnebox < ApplicationService
    SECTION_PATH = %r{\A/forum/sections/([\w-]+)\z}i

    def initialize(url:)
      @url = url.to_s.strip
    end

    def call
      path = @url.start_with?("/") ? @url : URI.parse(@url).path
      match = path.match(SECTION_PATH)
      return ServiceResult.success(nil) unless match

      section = Community::Section.includes(:category).find_by(slug: match[1])
      return ServiceResult.success(nil) unless section

      meta = [ section.category&.name, "#{section.topics.where(status: :published).count} 主题" ].compact.join(" · ")
      ServiceResult.success(
        slug: section.slug,
        name: section.name,
        description: section.description.to_s.truncate(120),
        meta: meta,
        url: "#{Mcweb::Paths::APP_PREFIX}/forum/sections/#{section.slug}"
      )
    rescue URI::InvalidURIError
      ServiceResult.success(nil)
    end
  end
end

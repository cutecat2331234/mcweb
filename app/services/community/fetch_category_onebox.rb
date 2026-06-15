# frozen_string_literal: true

module Community
  class FetchCategoryOnebox < ApplicationService
    CATEGORY_PATH = %r{\A/forum/categories/([\w-]+)\z}i

    def initialize(url:)
      @url = url.to_s.strip
    end

    def call
      path = @url.start_with?("/") ? @url : URI.parse(@url).path
      match = path.match(CATEGORY_PATH)
      return ServiceResult.success(nil) unless match

      category = Community::Category.find_by(slug: match[1])
      return ServiceResult.success(nil) unless category

      section_count = Community::Section.where(forum_category_id: category.id).count
      ServiceResult.success(
        slug: category.slug,
        name: category.name,
        description: category.description.to_s.truncate(120),
        section_count: section_count,
        url: "/forum/categories/#{category.slug}"
      )
    rescue URI::InvalidURIError
      ServiceResult.success(nil)
    end
  end
end

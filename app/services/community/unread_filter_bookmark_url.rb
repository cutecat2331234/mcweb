# frozen_string_literal: true

module Community
  class UnreadFilterBookmarkUrl
    def self.call(base_url:, sort:, filter:, section:, tags:, tag_match:)
      new(
        base_url: base_url,
        sort: sort,
        filter: filter,
        section: section,
        tags: tags,
        tag_match: tag_match
      ).url
    end

    def initialize(base_url:, sort:, filter:, section:, tags:, tag_match:)
      @base_url = base_url.to_s.chomp("/")
      @sort = sort.to_s
      @filter = filter.to_s
      @section = section.to_s
      @tags = Array(tags)
      @tag_match = tag_match.to_s
    end

    def url
      return if params.empty?

      "#{@base_url}#{Rails.application.routes.url_helpers.forum_unread_path(params)}"
    end

  private

    def params
      items = {}
      items[:sort] = @sort if @sort.present? && @sort != "latest"
      items[:filter] = @filter if @filter.present?
      items[:section] = @section if @section.present?
      items[:tags] = @tags.join(",") if @tags.any?
      items[:tag_match] = @tag_match if @tag_match.present? && @tag_match != "all"
      items
    end
  end
end

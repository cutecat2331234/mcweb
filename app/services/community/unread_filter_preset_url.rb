# frozen_string_literal: true

module Community
  class UnreadFilterPresetUrl
    def self.call(base_url:, filters:)
      new(base_url: base_url, filters: filters).url
    end

    def initialize(base_url:, filters:)
      @base_url = base_url.to_s.chomp("/")
      @filters = filters.to_h.symbolize_keys
    end

    def url
      return if params.empty?

      "#{@base_url}#{Rails.application.routes.url_helpers.forum_unread_path(params)}"
    end

  private

    def params
      items = {}
      sort = @filters[:sort].to_s
      items[:sort] = sort if sort.present? && sort != "latest"
      items[:filter] = @filters[:filter] if @filters[:filter].present?
      items[:section] = @filters[:section] if @filters[:section].present?
      tags = @filters[:tags].to_s
      items[:tags] = tags if tags.present?
      tag_match = @filters[:tag_match].to_s
      items[:tag_match] = tag_match if tag_match.present? && tag_match != "all"
      items
    end
  end
end

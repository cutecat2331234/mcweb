# frozen_string_literal: true

module Community
  class SavedSearchMatcher
    def initialize(saved_search)
      @saved_search = saved_search
    end

    def matching_topics(since: nil)
      raw = @saved_search.query.to_s.strip
      parsed = Community::ParseSearchQuery.call(query: raw)
      query = parsed.success? ? parsed.value[:query].to_s.strip : raw
      filters = @saved_search.filters.symbolize_keys

      scope = Community::Topic.published_listed
      scope = scope.where("forum_topics.created_at > ?", since) if since

      section_slug = filters[:section].presence
      scope = scope.joins(:section).where(forum_sections: { slug: section_slug }) if section_slug

      category_slug = filters[:category].presence
      if category_slug
        category = Community::Category.find_by(slug: category_slug)
        if category
          section_ids = Community::Section.where(forum_category_id: category.id).select(:id)
          scope = scope.where(forum_section_id: section_ids)
        else
          scope = scope.none
        end
      end

      if filters[:solved].present?
        scope = case filters[:solved]
        when "solved" then scope.where.not(solved_at: nil)
        when "unsolved" then scope.where(solved_at: nil)
        else scope
        end
      end

      if query.present?
        scope = scope.where(
          "to_tsvector('simple', coalesce(forum_topics.title, '')) @@ plainto_tsquery('simple', ?)",
          query
        )
      end

      scope.order(created_at: :desc)
    end
  end
end

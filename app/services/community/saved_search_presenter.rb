# frozen_string_literal: true

module Community
  module SavedSearchPresenter
    module_function

    def url_params(search)
      filters = search.filters.symbolize_keys
      {
        q: search.query.presence,
        section: filters[:section].presence,
        category: filters[:category].presence,
        author: filters[:author].presence,
        tag: filters[:tag].presence,
        solved: filters[:solved].presence,
        locked: filters[:locked].presence,
        pinned: filters[:pinned].presence,
        wiki: filters[:wiki].presence,
        featured: filters[:featured].presence,
        announcement: filters[:announcement].presence,
        assigned: filters[:assigned].presence,
        assignee: filters[:assignee].presence,
        unlisted: filters[:unlisted].presence,
        archived: filters[:archived].presence,
        mine: filters[:mine].presence,
        scope: filters[:scope].presence,
        poll: filters[:poll].presence,
        noreplies: filters[:noreplies].presence,
        images: filters[:images].presence,
        created_after: filters[:created_after].presence,
        created_before: filters[:created_before].presence,
        topic_sort: filters[:topic_sort].presence,
        post_sort: filters[:post_sort].presence,
        title_only: filters[:title_only].presence
      }.compact
    end

    def rss_path(search)
      Rails.application.routes.url_helpers.forum_saved_search_rss_path(
        id: search.id,
        token: Community::SavedSearchRssToken.generate(search)
      )
    end

    def opml_path(user)
      Rails.application.routes.url_helpers.forum_saved_searches_opml_path(
        token: Community::SavedSearchOpmlToken.generate(user)
      )
    end
  end
end

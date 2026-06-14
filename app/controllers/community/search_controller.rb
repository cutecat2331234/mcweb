# frozen_string_literal: true

module Community
  class SearchController < ApplicationController
    include BlockedUsersFilterable

    def index
      query = params[:q].to_s.strip
      section_slug = params[:section].to_s.presence
      topics = Community::Topic.none
      posts = Community::Post.none

      if query.present?
        topics = Community::Topic.where(status: :published)
        topics = topics.joins(:section).where(forum_sections: { slug: section_slug }) if section_slug
        topics = topics.where(
          "to_tsvector('simple', coalesce(forum_topics.title, '')) @@ plainto_tsquery('simple', ?)",
          query
        ).order(last_posted_at: :desc)
        topics = filter_blocked_topics(topics)

        posts = Community::Post.where(status: :published)
        posts = posts.joins(topic: :section).where(forum_sections: { slug: section_slug }) if section_slug
        posts = posts.where(
          "to_tsvector('simple', coalesce(forum_posts.body, '')) @@ plainto_tsquery('simple', ?)",
          query
        ).includes(:user, topic: :section).order(created_at: :desc)
        posts = filter_blocked_posts(posts)
      end

      @pagy_topics, topics = pagy(topics, limit: 15, page_param: :topic_page)
      @pagy_posts, posts = pagy(posts, limit: 15, page_param: :post_page)

      sections = Community::Section.ordered.includes(:category).map do |section|
        { slug: section.slug, name: section.name, category: section.category&.name }
      end

      render inertia: "Community/Search/Index", props: {
        query: query,
        section: section_slug,
        sections: sections,
        topics: topics.map { |topic| serialize_search_topic(topic) },
        posts: posts.map { |post| serialize_search_post(post) },
        topicsPagination: pagy_props(@pagy_topics),
        postsPagination: pagy_props(@pagy_posts)
      }
    end
  end
end

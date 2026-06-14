# frozen_string_literal: true

module Community
  class SearchController < ApplicationController
    include BlockedUsersFilterable

    def index
      query = params[:q].to_s.strip
      section_slug = params[:section].to_s.presence
      author = params[:author].to_s.strip.presence
      tag_slug = params[:tag].to_s.strip.presence
      solved_filter = params[:solved].to_s.presence
      topics = Community::Topic.none
      posts = Community::Post.none

      if query.present?
        topics = Community::Topic.where(status: :published)
        topics = topics.joins(:section).where(forum_sections: { slug: section_slug }) if section_slug
        topics = topics.joins(:user).where("users.username ILIKE ?", "%#{author}%") if author
        topics = topics.joins(:tags).where(forum_tags: { slug: tag_slug }) if tag_slug
        topics = topics.where(solved_post_id: nil) if solved_filter == "unsolved"
        topics = topics.where.not(solved_post_id: nil) if solved_filter == "solved"
        topics = topics.where(
          "to_tsvector('simple', coalesce(forum_topics.title, '')) @@ plainto_tsquery('simple', ?)",
          query
        ).order(last_posted_at: :desc)
        topics = filter_blocked_topics(topics)

        posts = Community::Post.where(status: :published)
        posts = posts.joins(topic: :section).where(forum_sections: { slug: section_slug }) if section_slug
        posts = posts.joins(:user).where("users.username ILIKE ?", "%#{author}%") if author
        posts = posts.joins(topic: :tags).where(forum_tags: { slug: tag_slug }) if tag_slug
        if solved_filter == "unsolved"
          posts = posts.joins(:topic).where(forum_topics: { solved_post_id: nil })
        elsif solved_filter == "solved"
          posts = posts.joins(:topic).where.not(forum_topics: { solved_post_id: nil })
        end
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

      tags = Community::Tag.usable_by(current_user).order(:name).limit(50).map { |tag| { slug: tag.slug, name: tag.name } }

      render inertia: "Community/Search/Index", props: {
        query: query,
        section: section_slug,
        author: author.to_s,
        tag: tag_slug.to_s,
        solved: solved_filter.to_s,
        sections: sections,
        tags: tags,
        topics: topics.map { |topic| serialize_search_topic(topic) },
        posts: posts.map { |post| serialize_search_post(post) },
        topicsPagination: pagy_props(@pagy_topics),
        postsPagination: pagy_props(@pagy_posts)
      }
    end
  end
end

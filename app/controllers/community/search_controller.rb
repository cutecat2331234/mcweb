# frozen_string_literal: true

module Community
  class SearchController < ApplicationController
    include BlockedUsersFilterable
    include Community::TopicListPreloadable

    def index
      raw_query = params[:q].to_s.strip
      parsed = Community::ParseSearchQuery.call(query: raw_query)
      parsed_query = parsed.success? ? parsed.value[:query] : raw_query
      parsed_section = parsed.success? ? parsed.value[:section_slug] : nil
      parsed_author = parsed.success? ? parsed.value[:author] : nil
      parsed_tag = parsed.success? ? parsed.value[:tag_slug] : nil
      parsed_solved = parsed.success? ? parsed.value[:solved_filter] : nil

      query = parsed_query
      section_slug = params[:section].to_s.presence || parsed_section
      author = params[:author].to_s.strip.presence || parsed_author
      tag_slug = params[:tag].to_s.strip.presence || parsed_tag
      solved_filter = params[:solved].to_s.presence || parsed_solved
      topics = Community::Topic.none
      posts = Community::Post.none

      if query.present?
        topics = Community::Topic.published_listed
        topics = topics.joins(:section).where(forum_sections: { slug: section_slug }) if section_slug
        topics = topics.joins(:user).where("users.username ILIKE ?", "%#{author}%") if author
        topics = topics.joins(:tags).where(forum_tags: { slug: tag_slug }) if tag_slug
        topics = topics.where(solved_post_id: nil) if solved_filter == "unsolved"
        topics = topics.where.not(solved_post_id: nil) if solved_filter == "solved"
        if params[:created_after].present?
          after = Time.zone.parse(params[:created_after].to_s) rescue nil
          topics = topics.where("forum_topics.created_at >= ?", after) if after
        end
        if params[:created_before].present?
          before = Time.zone.parse(params[:created_before].to_s) rescue nil
          topics = topics.where("forum_topics.created_at <= ?", before) if before
        end
        topics = topics.where(
          "to_tsvector('simple', coalesce(forum_topics.title, '')) @@ plainto_tsquery('simple', ?)",
          query
        )
        topics = case params[:topic_sort]
                 when "oldest" then topics.order(created_at: :asc)
                 else topics.order(last_posted_at: :desc)
                 end
        topics = filter_blocked_topics(topics)
        topics = preload_topics(topics)

        posts = Community::Post.where(status: :published).joins(:topic).where(forum_topics: { status: :published, unlisted: false })
        posts = posts.joins(topic: :section).where(forum_sections: { slug: section_slug }) if section_slug
        posts = posts.joins(:user).where("users.username ILIKE ?", "%#{author}%") if author
        posts = posts.joins(topic: :tags).where(forum_tags: { slug: tag_slug }) if tag_slug
        if solved_filter == "unsolved"
          posts = posts.joins(:topic).where(forum_topics: { solved_post_id: nil })
        elsif solved_filter == "solved"
          posts = posts.joins(:topic).where.not(forum_topics: { solved_post_id: nil })
        end
        if params[:created_after].present?
          after = Time.zone.parse(params[:created_after].to_s) rescue nil
          posts = posts.where("forum_posts.created_at >= ?", after) if after
        end
        if params[:created_before].present?
          before = Time.zone.parse(params[:created_before].to_s) rescue nil
          posts = posts.where("forum_posts.created_at <= ?", before) if before
        end
        posts = posts.where(
          "to_tsvector('simple', coalesce(forum_posts.body, '')) @@ plainto_tsquery('simple', ?)",
          query
        ).includes(:user, topic: :section)
        posts = case params[:post_sort]
                when "oldest" then posts.order(created_at: :asc)
                else posts.order(created_at: :desc)
                end
        posts = filter_blocked_posts(posts)
      end

      @pagy_topics, topics = pagy(topics, limit: 15, page_param: :topic_page)
      @pagy_posts, posts = pagy(posts, limit: 15, page_param: :post_page)

      sections = Community::Section.ordered.includes(:category).map do |section|
        { slug: section.slug, name: section.name, category: section.category&.name }
      end

      tags = Community::Tag.usable_by(current_user).order(:name).limit(50).map { |tag| { slug: tag.slug, name: tag.name } }

      render inertia: "Community/Search/Index", props: {
        query: raw_query,
        section: section_slug,
        author: author.to_s,
        tag: tag_slug.to_s,
        solved: solved_filter.to_s,
        createdAfter: params[:created_after].to_s,
        createdBefore: params[:created_before].to_s,
        topicSort: params[:topic_sort].to_s.presence || "recent",
        postSort: params[:post_sort].to_s.presence || "recent",
        sections: sections,
        tags: tags,
        topics: serialize_topics(topics),
        posts: posts.map { |post| serialize_search_post(post) },
        topicsPagination: pagy_props(@pagy_topics),
        postsPagination: pagy_props(@pagy_posts)
      }
    end
  end
end

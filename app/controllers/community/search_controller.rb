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
      parsed_locked = parsed.success? ? parsed.value[:locked_filter] : nil
      parsed_pinned = parsed.success? ? parsed.value[:pinned_filter] : nil
      parsed_wiki = parsed.success? ? parsed.value[:wiki_filter] : nil
      parsed_featured = parsed.success? ? parsed.value[:featured_filter] : nil
      parsed_announcement = parsed.success? ? parsed.value[:announcement_filter] : nil
      parsed_unlisted = parsed.success? ? parsed.value[:unlisted_filter] : nil
      parsed_poll = parsed.success? ? parsed.value[:poll_filter] : nil
      parsed_noreplies = parsed.success? ? parsed.value[:noreplies_filter] : nil

      query = parsed_query
      section_slug = params[:section].to_s.presence || parsed_section
      author = params[:author].to_s.strip.presence || parsed_author
      tag_slug = params[:tag].to_s.strip.presence || parsed_tag
      solved_filter = params[:solved].to_s.presence || parsed_solved
      locked_filter = params[:locked].to_s.presence || parsed_locked
      pinned_filter = params[:pinned].to_s.presence || parsed_pinned
      wiki_filter = params[:wiki].to_s.presence || parsed_wiki
      featured_filter = params[:featured].to_s.presence || parsed_featured
      announcement_filter = params[:announcement].to_s.presence || parsed_announcement
      unlisted_filter = params[:unlisted].to_s.presence || parsed_unlisted
      poll_filter = params[:poll].to_s.presence || parsed_poll
      noreplies_filter = params[:noreplies].to_s.presence || parsed_noreplies
      topics = Community::Topic.none
      posts = Community::Post.none

      if query.present?
        topics = search_topic_base_scope(unlisted_filter: unlisted_filter)
        topics = topics.joins(:section).where(forum_sections: { slug: section_slug }) if section_slug
        topics = topics.joins(:user).where("users.username ILIKE ?", "%#{author}%") if author
        topics = topics.joins(:tags).where(forum_tags: { slug: tag_slug }) if tag_slug
        topics = apply_search_topic_filters(
          topics,
          solved_filter: solved_filter,
          locked_filter: locked_filter,
          pinned_filter: pinned_filter,
          wiki_filter: wiki_filter,
          featured_filter: featured_filter,
          announcement_filter: announcement_filter,
          unlisted_filter: effective_unlisted_filter(unlisted_filter),
          poll_filter: poll_filter,
          noreplies_filter: noreplies_filter
        )
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
        posts = apply_search_topic_filters_on_posts(
          posts,
          solved_filter: solved_filter,
          locked_filter: locked_filter,
          pinned_filter: pinned_filter,
          wiki_filter: wiki_filter,
          featured_filter: featured_filter,
          announcement_filter: announcement_filter,
          unlisted_filter: effective_unlisted_filter(unlisted_filter),
          poll_filter: poll_filter,
          noreplies_filter: noreplies_filter
        )
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
        locked: locked_filter.to_s,
        pinned: pinned_filter.to_s,
        wiki: wiki_filter.to_s,
        featured: featured_filter.to_s,
        announcement: announcement_filter.to_s,
        unlisted: unlisted_filter.to_s,
        poll: poll_filter.to_s,
        noreplies: noreplies_filter.to_s,
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

    private

    def apply_search_topic_filters(scope, solved_filter:, locked_filter:, pinned_filter:, wiki_filter:, featured_filter: nil, announcement_filter: nil, unlisted_filter: nil, poll_filter: nil, noreplies_filter: nil)
      result = Community::ApplyTopicSearchFilters.call(
        scope: scope,
        solved_filter: solved_filter,
        locked_filter: locked_filter,
        pinned_filter: pinned_filter,
        wiki_filter: wiki_filter,
        featured_filter: featured_filter,
        announcement_filter: announcement_filter,
        unlisted_filter: unlisted_filter,
        poll_filter: poll_filter,
        noreplies_filter: noreplies_filter
      )
      result.success? ? result.value : scope
    end

    def apply_search_topic_filters_on_posts(scope, solved_filter:, locked_filter:, pinned_filter:, wiki_filter:, featured_filter: nil, announcement_filter: nil, unlisted_filter: nil, poll_filter: nil, noreplies_filter: nil)
      needs_join = [ solved_filter, locked_filter, pinned_filter, wiki_filter, featured_filter, announcement_filter, unlisted_filter, poll_filter, noreplies_filter ].any?(&:present?)
      scope = scope.joins(:topic) if needs_join
      apply_search_topic_filters(
        scope,
        solved_filter: solved_filter,
        locked_filter: locked_filter,
        pinned_filter: pinned_filter,
        wiki_filter: wiki_filter,
        featured_filter: featured_filter,
        announcement_filter: announcement_filter,
        unlisted_filter: unlisted_filter,
        poll_filter: poll_filter,
        noreplies_filter: noreplies_filter
      )
    end

    def search_topic_base_scope(unlisted_filter:)
      if unlisted_filter == "unlisted" && forum_staff?
        Community::Topic.where(status: :published, unlisted: true)
      else
        Community::Topic.published_listed
      end
    end

    def effective_unlisted_filter(unlisted_filter)
      return nil unless unlisted_filter == "unlisted"
      return "unlisted" if forum_staff?

      nil
    end

    def forum_staff?
      current_user&.permission?("forum.topics.lock")
    end
  end
end

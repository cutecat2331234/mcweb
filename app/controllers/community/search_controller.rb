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
      parsed_archived = parsed.success? ? parsed.value[:archived_filter] : nil
      parsed_assigned = parsed.success? ? parsed.value[:assigned_filter] : nil
      parsed_assignee = parsed.success? ? parsed.value[:assignee_filter] : nil
      parsed_mine = parsed.success? ? parsed.value[:mine_filter] : nil
      parsed_scope = parsed.success? ? parsed.value[:scope_filter] : nil
      parsed_poll = parsed.success? ? parsed.value[:poll_filter] : nil
      parsed_noreplies = parsed.success? ? parsed.value[:noreplies_filter] : nil
      parsed_images = parsed.success? ? parsed.value[:images_filter] : nil
      parsed_category = parsed.success? ? parsed.value[:category_slug] : nil
      parsed_title_only = parsed.success? ? parsed.value[:title_only_filter] : nil
      parsed_posts_only = parsed.success? ? parsed.value[:posts_only_filter] : nil

      query = parsed_query
      title_only = !parsed_posts_only && (ActiveModel::Type::Boolean.new.cast(params[:title_only]) || parsed_title_only.present?)
      posts_only = !title_only && (ActiveModel::Type::Boolean.new.cast(params[:posts_only]) || parsed_posts_only.present?)
      section_slug = params[:section].to_s.presence || parsed_section
      category_slug = params[:category].to_s.presence || parsed_category
      author = params[:author].to_s.strip.presence || parsed_author
      tag_slug = params[:tag].to_s.strip.presence || parsed_tag
      solved_filter = params[:solved].to_s.presence || parsed_solved
      locked_filter = params[:locked].to_s.presence || parsed_locked
      pinned_filter = params[:pinned].to_s.presence || parsed_pinned
      wiki_filter = params[:wiki].to_s.presence || parsed_wiki
      featured_filter = params[:featured].to_s.presence || parsed_featured
      announcement_filter = params[:announcement].to_s.presence || parsed_announcement
      unlisted_filter = params[:unlisted].to_s.presence || parsed_unlisted
      archived_filter = params[:archived].to_s.presence || parsed_archived
      assigned_filter = params[:assigned].to_s.presence || parsed_assigned
      assignee_filter = params[:assignee].to_s.presence || parsed_assignee
      mine_filter = params[:mine].to_s.presence || parsed_mine
      scope_filter = params[:scope].to_s.presence || parsed_scope
      poll_filter = params[:poll].to_s.presence || parsed_poll
      noreplies_filter = params[:noreplies].to_s.presence || parsed_noreplies
      images_filter = params[:images].to_s.presence || parsed_images
      topics = Community::Topic.none
      posts = Community::Post.none

      assignee_id = resolve_assignee_id(assignee_filter)

      if query.present?
        unless posts_only
        topics = search_topic_base_scope(unlisted_filter: unlisted_filter, archived_filter: archived_filter)
        topics = apply_user_search_scope(topics, mine_filter: mine_filter, scope_filter: scope_filter)
        topics = topics.joins(:section).where(forum_sections: { slug: section_slug }) if section_slug
        topics = apply_category_filter(topics, category_slug) if category_slug
        topics = topics.joins(:user).where("users.username ILIKE ?", "%#{author}%") if author
        topics = apply_tag_filter(topics, tag_slug) if tag_slug
        topics = apply_search_topic_filters(
          topics,
          solved_filter: solved_filter,
          locked_filter: locked_filter,
          pinned_filter: pinned_filter,
          wiki_filter: wiki_filter,
          featured_filter: featured_filter,
          announcement_filter: announcement_filter,
          unlisted_filter: effective_unlisted_filter(unlisted_filter),
          archived_filter: effective_archived_filter(archived_filter),
          assigned_filter: assigned_filter,
          assignee_id: assignee_id,
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
        when "relevance"
          topics.order(Arel.sql("ts_rank(to_tsvector('simple', coalesce(forum_topics.title, '')), plainto_tsquery('simple', #{ActiveRecord::Base.connection.quote(query)})) DESC"))
        else topics.order(last_posted_at: :desc)
        end
        topics = filter_blocked_topics(topics)
        topics = preload_topics(topics)
        end

        posts = if title_only
          Community::Post.none
        else
          Community::Post.where(status: :published).joins(:topic).where(forum_topics: { status: :published, unlisted: false })
        end
        unless title_only
        posts = apply_user_search_scope(posts, mine_filter: mine_filter, scope_filter: scope_filter, on_posts: true)
        posts = posts.joins(topic: :section).where(forum_sections: { slug: section_slug }) if section_slug
        posts = apply_category_filter_on_posts(posts, category_slug) if category_slug
        posts = posts.joins(:user).where("users.username ILIKE ?", "%#{author}%") if author
        posts = apply_tag_filter_on_posts(posts, tag_slug) if tag_slug
        posts = apply_images_filter(posts) if images_filter == "images"
        posts = apply_search_topic_filters_on_posts(
          posts,
          solved_filter: solved_filter,
          locked_filter: locked_filter,
          pinned_filter: pinned_filter,
          wiki_filter: wiki_filter,
          featured_filter: featured_filter,
          announcement_filter: announcement_filter,
          unlisted_filter: effective_unlisted_filter(unlisted_filter),
          archived_filter: effective_archived_filter(archived_filter),
          assigned_filter: assigned_filter,
          assignee_id: assignee_id,
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
        when "relevance"
          posts.order(Arel.sql("ts_rank(to_tsvector('simple', coalesce(forum_posts.body, '')), plainto_tsquery('simple', #{ActiveRecord::Base.connection.quote(query)})) DESC"))
        else posts.order(created_at: :desc)
        end
        posts = filter_blocked_posts(posts)
        end
      end

      @pagy_topics, topics = pagy(topics, limit: 15, page_param: :topic_page)
      @pagy_posts, posts = pagy(posts, limit: 15, page_param: :post_page)

      sections = Community::Section.ordered.includes(:category).map do |section|
        { slug: section.slug, name: section.name, category: section.category&.name }
      end

      tags = Community::Tag.usable_by(current_user).order(:name).limit(50).map { |tag| { slug: tag.slug, name: tag.name } }

      categories = Community::Category.ordered.map do |category|
        { slug: category.slug, name: category.name }
      end

      render inertia: "Community/Search/Index", props: {
        query: raw_query,
        section: section_slug,
        category: category_slug.to_s,
        author: author.to_s,
        tag: tag_slug.to_s,
        solved: solved_filter.to_s,
        locked: locked_filter.to_s,
        pinned: pinned_filter.to_s,
        wiki: wiki_filter.to_s,
        featured: featured_filter.to_s,
        announcement: announcement_filter.to_s,
        unlisted: unlisted_filter.to_s,
        archived: archived_filter.to_s,
        assigned: assigned_filter.to_s,
        assignee: assignee_filter.to_s,
        mine: mine_filter.to_s,
        scope: scope_filter.to_s,
        poll: poll_filter.to_s,
        noreplies: noreplies_filter.to_s,
        titleOnly: title_only,
        postsOnly: posts_only,
        images: images_filter.to_s,
        createdAfter: params[:created_after].to_s,
        createdBefore: params[:created_before].to_s,
        topicSort: params[:topic_sort].to_s.presence || "recent",
        postSort: params[:post_sort].to_s.presence || "recent",
        sections: sections,
        categories: categories,
        tags: tags,
        topics: serialize_topics(topics),
        posts: posts.map { |post| serialize_search_post(post, query: query) },
        topicsPagination: pagy_props(@pagy_topics),
        postsPagination: pagy_props(@pagy_posts),
        savedSearches: serialize_saved_searches,
        loggedIn: logged_in?,
        forumStaff: forum_staff?,
        saveSearchUrl: logged_in? ? forum_saved_searches_path : nil,
        savedSearchLimit: Community::SavedSearch.limit_for_user(current_user).finite? ? Community::SavedSearch.limit_for_user(current_user).to_i : nil,
        savedSearchCount: logged_in? ? current_user.forum_saved_searches.count : 0,
        savedSearchesOpmlUrl: logged_in? ? Community::SavedSearchPresenter.opml_path(current_user) : nil,
        suggestUrl: forum_search_suggest_path
      }
    end

    def suggest
      q = params[:q].to_s.strip
      if q.length < 2
        return render json: { topics: [], tags: [], users: [] }
      end

      needle = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
      topics = Community::Topic.published_listed
        .where("title ILIKE ?", needle)
        .order(last_posted_at: :desc)
        .limit(5)
        .map { |topic| { title: topic.title, url: forum_topic_path(topic) } }

      tags = Community::Tag.usable_by(current_user)
        .where("name ILIKE ? OR slug ILIKE ?", needle, needle)
        .order(:name)
        .limit(10)
        .map(&:effective_tag)
        .uniq
        .first(5)
        .map { |tag| { name: tag.name, url: forum_tag_path(tag.slug) } }

      users = User.where(status: :active)
        .where("username ILIKE ? OR display_name ILIKE ?", needle, needle)
        .order(:username)
        .limit(5)
        .map { |user| { username: user.username, url: forum_user_path(user.username) } }

      sections = Community::Section.joins(:category)
        .where("forum_sections.name ILIKE ? OR forum_sections.slug ILIKE ?", needle, needle)
        .order("forum_sections.name")
        .limit(5)
        .map do |section|
          {
            name: section.name,
            category: section.category&.name,
            url: forum_section_path(section)
          }
        end

      saved_searches = if logged_in?
        current_user.forum_saved_searches
          .where("name ILIKE ?", needle)
          .recent
          .limit(5)
          .map do |search|
            {
              name: search.name,
              url: forum_search_path(Community::SavedSearchPresenter.url_params(search))
            }
          end
      else
        []
      end

      render json: { topics: topics, tags: tags, users: users, sections: sections, saved_searches: saved_searches }
    end

    private

    def apply_user_search_scope(scope, mine_filter:, scope_filter:, on_posts: false)
      return scope unless logged_in?

      if mine_filter == "mine"
        return on_posts ? scope.where(user_id: current_user.id) : scope.where(user_id: current_user.id)
      end

      if scope_filter == "bookmarks"
        bookmark_topic_ids = Community::Bookmark.where(user: current_user).select(:forum_topic_id)
        return on_posts ? scope.where(forum_topic_id: bookmark_topic_ids) : scope.where(id: bookmark_topic_ids)
      end

      if scope_filter == "watching"
        topic_ids = Community::Subscription.where(user: current_user, subscribable_type: "Community::Topic").select(:subscribable_id)
        return on_posts ? scope.where(forum_topic_id: topic_ids) : scope.where(id: topic_ids)
      end

      if scope_filter == "unread"
        unread_topic_ids = Community::ReadState.with_unread_for(current_user).select(:forum_topic_id)
        return on_posts ? scope.where(forum_topic_id: unread_topic_ids) : scope.where(id: unread_topic_ids)
      end

      scope
    end

    def resolve_assignee_id(assignee_filter)
      return nil if assignee_filter.blank?

      if assignee_filter == "me"
        return current_user&.id
      end

      User.find_by(username: assignee_filter)&.id
    end

    def apply_search_topic_filters(scope, solved_filter:, locked_filter:, pinned_filter:, wiki_filter:, featured_filter: nil, announcement_filter: nil, unlisted_filter: nil, archived_filter: nil, assigned_filter: nil, assignee_id: nil, poll_filter: nil, noreplies_filter: nil)
      result = Community::ApplyTopicSearchFilters.call(
        scope: scope,
        solved_filter: solved_filter,
        locked_filter: locked_filter,
        pinned_filter: pinned_filter,
        wiki_filter: wiki_filter,
        featured_filter: featured_filter,
        announcement_filter: announcement_filter,
        unlisted_filter: unlisted_filter,
        archived_filter: archived_filter,
        assigned_filter: assigned_filter,
        assignee_id: assignee_id,
        poll_filter: poll_filter,
        noreplies_filter: noreplies_filter
      )
      result.success? ? result.value : scope
    end

    def apply_search_topic_filters_on_posts(scope, solved_filter:, locked_filter:, pinned_filter:, wiki_filter:, featured_filter: nil, announcement_filter: nil, unlisted_filter: nil, archived_filter: nil, assigned_filter: nil, assignee_id: nil, poll_filter: nil, noreplies_filter: nil)
      needs_join = [ solved_filter, locked_filter, pinned_filter, wiki_filter, featured_filter, announcement_filter, unlisted_filter, archived_filter, assigned_filter, assignee_id, poll_filter, noreplies_filter ].any?(&:present?)
      scope = scope.joins(:topic) if needs_join
      result = Community::ApplyTopicSearchFilters.call(
        scope: scope,
        solved_filter: solved_filter,
        locked_filter: locked_filter,
        pinned_filter: pinned_filter,
        wiki_filter: wiki_filter,
        featured_filter: featured_filter,
        announcement_filter: announcement_filter,
        unlisted_filter: unlisted_filter,
        archived_filter: archived_filter,
        assigned_filter: assigned_filter,
        assignee_id: assignee_id,
        poll_filter: poll_filter,
        noreplies_filter: noreplies_filter,
        table_prefix: "forum_topics"
      )
      result.success? ? result.value : scope
    end

    def search_topic_base_scope(unlisted_filter:, archived_filter: nil)
      if archived_filter == "archived" && forum_staff?
        Community::Topic.where(status: :published).where.not(archived_at: nil)
      elsif unlisted_filter == "unlisted" && forum_staff?
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

    def effective_archived_filter(archived_filter)
      return nil unless archived_filter == "archived"
      return "archived" if forum_staff?

      nil
    end

    def forum_staff?
      current_user&.permission?("forum.topics.lock")
    end

    def apply_category_filter(scope, category_slug)
      category = Community::Category.find_by(slug: category_slug)
      return scope.none unless category

      section_ids = Community::Section.where(forum_category_id: category.id).select(:id)
      scope.where(forum_section_id: section_ids)
    end

    def apply_category_filter_on_posts(scope, category_slug)
      category = Community::Category.find_by(slug: category_slug)
      return scope.none unless category

      section_ids = Community::Section.where(forum_category_id: category.id).select(:id)
      scope.where(forum_topics: { forum_section_id: section_ids })
    end

    def apply_tag_filter(scope, tag_slug)
      tag_ids = resolved_tag_ids(tag_slug)
      return scope.none if tag_ids.empty?

      scope.joins(:tags).where(forum_tags: { id: tag_ids })
    end

    def apply_tag_filter_on_posts(scope, tag_slug)
      tag_ids = resolved_tag_ids(tag_slug)
      return scope.none if tag_ids.empty?

      scope.joins(topic: :tags).where(forum_tags: { id: tag_ids })
    end

    def resolved_tag_ids(tag_slug)
      tag = Community::Tag.resolve_by_slug(tag_slug) || Community::Tag.find_by(slug: tag_slug)
      return [] unless tag

      canonical = tag.canonical_tag || tag
      [ canonical.id ] + Community::Tag.where(canonical_tag_id: canonical.id).pluck(:id)
    end

    def apply_images_filter(scope)
      scope.where("forum_posts.body LIKE ? OR forum_posts.body LIKE ?", "%![%", "%/rails/active_storage/%")
    end

    def serialize_saved_searches
      return [] unless logged_in?

      current_user.forum_saved_searches.recent.limit(10).map do |search|
        {
          id: search.id,
          name: search.name,
          query: search.query,
          notify_daily: search.notify_daily?,
          filter_labels: Community::SavedSearchFilterSummary.call(search),
          url: forum_search_path(Community::SavedSearchPresenter.url_params(search)),
          rss_url: Community::SavedSearchPresenter.rss_path(search),
          webhook_url: search.webhook_url,
          update_url: forum_saved_search_path(search),
          delete_url: forum_saved_search_path(search)
        }
      end
    end

    def saved_search_url_params(search)
      Community::SavedSearchPresenter.url_params(search)
    end
  end
end

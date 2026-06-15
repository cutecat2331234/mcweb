# frozen_string_literal: true

module Community
  class BuildSavedSearchTopicScope < ApplicationService
    def initialize(saved_search:, since: nil)
      @saved_search = saved_search
      @user = saved_search.user
      @since = since
      @stored_filters = saved_search.filters.symbolize_keys
    end

    def call
      parsed = parse_query
      filters = merged_filters(parsed)
      query = filters.delete(:query).to_s.strip

      scope = base_scope(filters)
      scope = scope.where("forum_topics.created_at > ?", @since) if @since
      scope = apply_section(scope, filters[:section])
      scope = apply_category(scope, filters[:category])
      scope = apply_author(scope, filters[:author])
      scope = apply_tag(scope, filters[:tag])
      scope = apply_topic_filters(scope, filters)
      scope = apply_user_scope(scope, filters)
      scope = apply_dates(scope, filters)
      scope = apply_query(scope, query) if query.present?
      scope = apply_exclusions(scope, filters[:exclude_terms])
      scope = apply_sort(scope, filters[:topic_sort])

      ServiceResult.success(scope)
    end

  private

    def parse_query
      raw = @saved_search.query.to_s.strip
      result = Community::ParseSearchQuery.call(query: raw)
      result.success? ? result.value : { query: raw }
    end

    def merged_filters(parsed)
      {
        query: @stored_filters[:query].presence || parsed[:query],
        section: @stored_filters[:section].presence || parsed[:section_slug],
        category: @stored_filters[:category].presence || parsed[:category_slug],
        author: @stored_filters[:author].presence || parsed[:author],
        tag: @stored_filters[:tag].presence || parsed[:tag_slug],
        solved: @stored_filters[:solved].presence || parsed[:solved_filter],
        locked: @stored_filters[:locked].presence || parsed[:locked_filter],
        pinned: @stored_filters[:pinned].presence || parsed[:pinned_filter],
        wiki: @stored_filters[:wiki].presence || parsed[:wiki_filter],
        featured: @stored_filters[:featured].presence || parsed[:featured_filter],
        announcement: @stored_filters[:announcement].presence || parsed[:announcement_filter],
        unlisted: @stored_filters[:unlisted].presence || parsed[:unlisted_filter],
        archived: @stored_filters[:archived].presence || parsed[:archived_filter],
        assigned: @stored_filters[:assigned].presence || parsed[:assigned_filter],
        assignee: @stored_filters[:assignee].presence || parsed[:assignee_filter],
        mine: @stored_filters[:mine].presence || parsed[:mine_filter],
        scope: @stored_filters[:scope].presence || parsed[:scope_filter],
        poll: @stored_filters[:poll].presence || parsed[:poll_filter],
        noreplies: @stored_filters[:noreplies].presence || parsed[:noreplies_filter],
        created_after: @stored_filters[:created_after].presence,
        created_before: @stored_filters[:created_before].presence,
        topic_sort: @stored_filters[:topic_sort].presence,
        exclude_terms: parsed[:exclude_terms] || []
      }
    end

    def base_scope(filters)
      if filters[:archived] == "archived" && forum_staff?
        Community::Topic.where(status: :published).where.not(archived_at: nil)
      elsif filters[:unlisted] == "unlisted" && forum_staff?
        Community::Topic.where(status: :published, unlisted: true)
      else
        Community::Topic.published_listed
      end
    end

    def apply_section(scope, section_slug)
      return scope if section_slug.blank?

      scope.joins(:section).where(forum_sections: { slug: section_slug })
    end

    def apply_category(scope, category_slug)
      return scope if category_slug.blank?

      category = Community::Category.find_by(slug: category_slug)
      return scope.none unless category

      section_ids = Community::Section.where(forum_category_id: category.id).select(:id)
      scope.where(forum_section_id: section_ids)
    end

    def apply_author(scope, author)
      return scope if author.blank?

      scope.joins(:user).where("users.username ILIKE ?", "%#{author}%")
    end

    def apply_tag(scope, tag_slug)
      return scope if tag_slug.blank?

      tag_ids = resolved_tag_ids(tag_slug)
      return scope.none if tag_ids.empty?

      scope.joins(:tags).where(forum_tags: { id: tag_ids })
    end

    def resolved_tag_ids(tag_slug)
      canonical = Community::Tag.find_by(slug: tag_slug)
      return [] unless canonical

      [ canonical.id ] + Community::Tag.where(canonical_tag_id: canonical.id).pluck(:id)
    end

    def apply_topic_filters(scope, filters)
      assignee_id = resolve_assignee_id(filters[:assignee])
      unlisted = filters[:unlisted] == "unlisted" && forum_staff? ? "unlisted" : nil
      archived = filters[:archived] == "archived" && forum_staff? ? "archived" : nil

      result = Community::ApplyTopicSearchFilters.call(
        scope: scope,
        solved_filter: filters[:solved],
        locked_filter: filters[:locked],
        pinned_filter: filters[:pinned],
        wiki_filter: filters[:wiki],
        featured_filter: filters[:featured],
        announcement_filter: filters[:announcement],
        unlisted_filter: unlisted,
        archived_filter: archived,
        assigned_filter: filters[:assigned],
        assignee_id: assignee_id,
        poll_filter: filters[:poll],
        noreplies_filter: filters[:noreplies]
      )
      result.success? ? result.value : scope
    end

    def apply_user_scope(scope, filters)
      if filters[:mine] == "mine"
        return scope.where(user_id: @user.id)
      end

      case filters[:scope]
      when "bookmarks"
        bookmark_topic_ids = Community::Bookmark.where(user: @user).select(:forum_topic_id)
        scope.where(id: bookmark_topic_ids)
      when "watching"
        topic_ids = Community::Subscription.where(user: @user, subscribable_type: "Community::Topic").select(:subscribable_id)
        scope.where(id: topic_ids)
      when "unread"
        unread_topic_ids = Community::ReadState.with_unread_for(@user).select(:forum_topic_id)
        scope.where(id: unread_topic_ids)
      else
        scope
      end
    end

    def apply_dates(scope, filters)
      if filters[:created_after].present?
        after = Time.zone.parse(filters[:created_after].to_s) rescue nil
        scope = scope.where("forum_topics.created_at >= ?", after) if after
      end
      if filters[:created_before].present?
        before = Time.zone.parse(filters[:created_before].to_s) rescue nil
        scope = scope.where("forum_topics.created_at <= ?", before) if before
      end
      scope
    end

    def apply_query(scope, query)
      scope.where(
        "to_tsvector('simple', coalesce(forum_topics.title, '')) @@ plainto_tsquery('simple', ?)",
        query
      )
    end

    def apply_exclusions(scope, exclude_terms)
      result = Community::ApplySearchExclusions.call(scope: scope, exclude_terms: exclude_terms)
      result.success? ? result.value : scope
    end

    def apply_sort(scope, topic_sort)
      case topic_sort
      when "oldest" then scope.order(created_at: :asc)
      else scope.order(created_at: :desc)
      end
    end

    def resolve_assignee_id(assignee_filter)
      return nil if assignee_filter.blank?

      return @user.id if assignee_filter == "me"

      User.find_by(username: assignee_filter)&.id
    end

    def forum_staff?
      @user.permission?("forum.topics.lock")
    end
  end
end

# frozen_string_literal: true

module Community
  class BuildAdHocSearchTopicScope < ApplicationService
    def initialize(params:, user: nil)
      @params = params.stringify_keys
      @user = user
    end

    def call
      query = @params["q"].to_s.strip
      return ServiceResult.success(scope: Community::Topic.none) if query.blank?
      return ServiceResult.success(scope: Community::Topic.none) if posts_only?

      parsed = Community::ParseSearchQuery.call(query: query)
      filters = merged_filters(parsed)

      scope = base_scope(filters)
      scope = apply_user_scope(scope, filters)
      scope = scope.joins(:section).where(forum_sections: { slug: filters[:section] }) if filters[:section].present?
      scope = apply_category(scope, filters[:category]) if filters[:category].present?
      scope = scope.joins(:user).where("users.username ILIKE ?", "%#{filters[:author]}%") if filters[:author].present?
      scope = apply_tag(scope, filters[:tag]) if filters[:tag].present?
      scope = apply_topic_filters(scope, filters)
      scope = apply_dates(scope, filters)
      scope = scope.where(
        "to_tsvector('simple', coalesce(forum_topics.title, '')) @@ plainto_tsquery('simple', ?)",
        query
      )
      scope = apply_sort(scope, filters[:topic_sort])
      ServiceResult.success(scope: scope)
    end

  private

    def posts_only?
      ActiveModel::Type::Boolean.new.cast(@params["posts_only"])
    end

    def merged_filters(parsed)
      value = parsed.success? ? parsed.value : {}
      {
        section: @params["section"].presence || value[:section_slug],
        category: @params["category"].presence || value[:category_slug],
        author: @params["author"].presence || value[:author],
        tag: @params["tag"].presence || value[:tag_slug],
        solved: @params["solved"].presence || value[:solved_filter],
        locked: @params["locked"].presence || value[:locked_filter],
        pinned: @params["pinned"].presence || value[:pinned_filter],
        wiki: @params["wiki"].presence || value[:wiki_filter],
        featured: @params["featured"].presence || value[:featured_filter],
        announcement: @params["announcement"].presence || value[:announcement_filter],
        unlisted: @params["unlisted"].presence || value[:unlisted_filter],
        archived: @params["archived"].presence || value[:archived_filter],
        assigned: @params["assigned"].presence || value[:assigned_filter],
        assignee: @params["assignee"].presence || value[:assignee_filter],
        mine: @params["mine"].presence || value[:mine_filter],
        scope: @params["scope"].presence || value[:scope_filter],
        poll: @params["poll"].presence || value[:poll_filter],
        noreplies: @params["noreplies"].presence || value[:noreplies_filter],
        created_after: @params["created_after"],
        created_before: @params["created_before"],
        topic_sort: @params["topic_sort"].presence || "recent"
      }
    end

    def forum_staff?
      @user&.permission?("forum.topics.lock")
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

    def apply_user_scope(scope, filters)
      return scope unless @user

      if filters[:mine] == "mine"
        return scope.where(user_id: @user.id)
      end

      case filters[:scope]
      when "bookmarks"
        bookmark_ids = Community::Bookmark.where(user: @user).select(:forum_topic_id)
        scope.where(id: bookmark_ids)
      when "watching"
        topic_ids = Community::Subscription.where(user: @user, subscribable_type: "Community::Topic").select(:subscribable_id)
        scope.where(id: topic_ids)
      when "unread"
        unread_ids = Community::ReadState.with_unread_for(@user).select(:forum_topic_id)
        scope.where(id: unread_ids)
      else
        scope
      end
    end

    def apply_category(scope, category_slug)
      category = Community::Category.find_by(slug: category_slug)
      return scope.none unless category

      section_ids = Community::Section.where(forum_category_id: category.id).select(:id)
      scope.where(forum_section_id: section_ids)
    end

    def apply_tag(scope, tag_slug)
      tag = Community::Tag.find_by(slug: tag_slug) || Community::Tag.find_by(name: tag_slug)
      return scope.none unless tag

      scope.joins(:tags).where(forum_tags: { id: tag.id })
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

    def resolve_assignee_id(assignee)
      return nil if assignee.blank?
      return @user&.id if assignee == "me"

      User.find_by(username: assignee)&.id
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

    def apply_sort(scope, topic_sort)
      query = @params["q"].to_s.strip
      case topic_sort
      when "oldest" then scope.order(created_at: :asc)
      when "relevance"
        scope.order(Arel.sql("ts_rank(to_tsvector('simple', coalesce(forum_topics.title, '')), plainto_tsquery('simple', #{ActiveRecord::Base.connection.quote(query)})) DESC"))
      else scope.order(last_posted_at: :desc)
      end
    end
  end
end

# frozen_string_literal: true

module Community
  class ApplyTopicSearchFilters < ApplicationService
    def initialize(scope:, solved_filter: nil, locked_filter: nil, pinned_filter: nil, wiki_filter: nil, featured_filter: nil, announcement_filter: nil, unlisted_filter: nil, archived_filter: nil, poll_filter: nil, noreplies_filter: nil)
      @scope = scope
      @solved_filter = solved_filter
      @locked_filter = locked_filter
      @pinned_filter = pinned_filter
      @wiki_filter = wiki_filter
      @featured_filter = featured_filter
      @announcement_filter = announcement_filter
      @unlisted_filter = unlisted_filter
      @archived_filter = archived_filter
      @poll_filter = poll_filter
      @noreplies_filter = noreplies_filter
    end

    def call
      scope = @scope
      scope = scope.where(solved_post_id: nil) if @solved_filter == "unsolved"
      scope = scope.where.not(solved_post_id: nil) if @solved_filter == "solved"
      scope = scope.where(locked: true) if @locked_filter == "locked"
      scope = scope.where(locked: false) if @locked_filter == "unlocked"
      scope = scope.where(pinned: true) if @pinned_filter == "pinned"
      scope = scope.where(wiki: true) if @wiki_filter == "wiki"
      scope = scope.where(featured: true) if @featured_filter == "featured"
      scope = scope.where(global_announcement: true) if @announcement_filter == "announcement"
      scope = scope.where(unlisted: true) if @unlisted_filter == "unlisted"
      scope = scope.where.not(archived_at: nil) if @archived_filter == "archived"
      scope = scope.where(id: Community::Poll.select(:forum_topic_id)) if @poll_filter == "poll"
      scope = scope.where(replies_count: 0) if @noreplies_filter == "noreplies"
      ServiceResult.success(scope)
    end
  end
end

# frozen_string_literal: true

module Community
  class ApplyTopicSearchFilters < ApplicationService
    def initialize(scope:, solved_filter: nil, locked_filter: nil, pinned_filter: nil, wiki_filter: nil, featured_filter: nil, announcement_filter: nil, unlisted_filter: nil, archived_filter: nil, assigned_filter: nil, assignee_id: nil, poll_filter: nil, noreplies_filter: nil, table_prefix: nil)
      @scope = scope
      @solved_filter = solved_filter
      @locked_filter = locked_filter
      @pinned_filter = pinned_filter
      @wiki_filter = wiki_filter
      @featured_filter = featured_filter
      @announcement_filter = announcement_filter
      @unlisted_filter = unlisted_filter
      @archived_filter = archived_filter
      @assigned_filter = assigned_filter
      @assignee_id = assignee_id
      @poll_filter = poll_filter
      @noreplies_filter = noreplies_filter
      @table_prefix = table_prefix
    end

    def call
      scope = @scope
      scope = scope.where(col("solved_post_id") => nil) if @solved_filter == "unsolved"
      scope = scope.where.not(col("solved_post_id") => nil) if @solved_filter == "solved"
      scope = scope.where(col("locked") => true) if @locked_filter == "locked"
      scope = scope.where(col("locked") => false) if @locked_filter == "unlocked"
      scope = scope.where(col("pinned") => true) if @pinned_filter == "pinned"
      scope = scope.where(col("wiki") => true) if @wiki_filter == "wiki"
      scope = scope.where(col("featured") => true) if @featured_filter == "featured"
      scope = scope.where(col("global_announcement") => true) if @announcement_filter == "announcement"
      scope = scope.where(col("unlisted") => true) if @unlisted_filter == "unlisted"
      scope = scope.where.not(col("archived_at") => nil) if @archived_filter == "archived"
      scope = scope.where.not(col("assigned_to_id") => nil) if @assigned_filter == "assigned"
      scope = scope.where(col("assigned_to_id") => nil) if @assigned_filter == "unassigned"
      scope = scope.where(col("assigned_to_id") => @assignee_id) if @assignee_id.present?
      scope = scope.where(col("id") => Community::Poll.select(:forum_topic_id)) if @poll_filter == "poll"
      scope = scope.where(col("replies_count") => 0) if @noreplies_filter == "noreplies"
      ServiceResult.success(scope)
    end

    private

    def col(name)
      @table_prefix ? "#{@table_prefix}.#{name}" : name
    end
  end
end

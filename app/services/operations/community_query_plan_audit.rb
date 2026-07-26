# frozen_string_literal: true

require "json"

module Operations
  # Runs PostgreSQL EXPLAIN without ANALYZE and returns a redacted plan summary.
  # Raw SQL, predicates, user identifiers, and search terms are intentionally
  # omitted so the report is safe to attach to operational tickets.
  class CommunityQueryPlanAudit
    SYNTHETIC_SEARCH_TERM = "mcweb_query_plan_probe"
    SYNTHETIC_USER_ID = -1

    def self.call
      new.call
    end

    def initialize
      @connection = ActiveRecord::Base.connection
    end

    def call
      unless @connection.adapter_name.casecmp?("PostgreSQL")
        raise ArgumentError, "community query-plan audit requires PostgreSQL"
      end

      {
        generated_at: Time.current.iso8601,
        adapter: @connection.adapter_name,
        analyze: false,
        redacted: true,
        queries: query_relations.map { |name, relation| explain(name, relation) }
      }
    end

    private

    def query_relations
      needle = "%#{SYNTHETIC_SEARCH_TERM}%"
      listed_topics = Community::Topic.published_listed
      listed_posts = Community::Post
        .where(status: :published)
        .joins(:topic)
        .where(forum_topics: {
          status: :published,
          unlisted: false,
          archived_at: nil,
          deleted_at: nil
        })

      {
        "full_text.topics" => listed_topics
          .where(
            "to_tsvector('simple', coalesce(forum_topics.title, '')) @@ plainto_tsquery('simple', ?)",
            SYNTHETIC_SEARCH_TERM
          )
          .order(last_posted_at: :desc)
          .limit(15),
        "full_text.posts" => listed_posts
          .where(
            "to_tsvector('simple', coalesce(forum_posts.body, '')) @@ plainto_tsquery('simple', ?)",
            SYNTHETIC_SEARCH_TERM
          )
          .order(created_at: :desc)
          .limit(15),
        "suggest.topics" => listed_topics
          .where("forum_topics.title ILIKE ?", needle)
          .order(last_posted_at: :desc)
          .limit(5),
        "suggest.tags" => Community::Tag
          .where(staff_only: false)
          .where("forum_tags.name ILIKE ? OR forum_tags.slug ILIKE ?", needle, needle)
          .order(:name)
          .limit(5),
        "suggest.users" => User
          .where(status: :active)
          .where("users.username ILIKE ? OR users.display_name ILIKE ?", needle, needle)
          .order(:username)
          .limit(5),
        "suggest.sections" => Community::Section
          .where("forum_sections.name ILIKE ? OR forum_sections.slug ILIKE ?", needle, needle)
          .order(:name)
          .limit(5),
        "top.window" => listed_topics
          .top_ranked(1.week.ago)
          .limit(30),
        "unread.exists" => Community::ReadState
          .with_unread_for_user_id(SYNTHETIC_USER_ID)
          .limit(20),
        "notifications.feed" => Notification
          .where(user_id: SYNTHETIC_USER_ID)
          .recent
          .limit(100),
        "notifications.unread_feed" => Notification
          .where(user_id: SYNTHETIC_USER_ID)
          .unread
          .recent
          .limit(100),
        "notifications.type_aggregate" => Notification
          .where(user_id: SYNTHETIC_USER_ID)
          .where(created_at: 30.days.ago..)
          .select(:notification_type, "COUNT(*) AS notifications_count")
          .group(:notification_type)
      }
    end

    def explain(name, relation)
      payload = JSON.parse(
        @connection.select_value("EXPLAIN (FORMAT JSON) #{relation.to_sql}")
      )
      root = payload.first.fetch("Plan")
      nodes = plan_nodes(root)

      {
        name: name,
        root_node: root.fetch("Node Type"),
        estimated_rows: root.fetch("Plan Rows"),
        total_cost: root.fetch("Total Cost"),
        node_types: nodes.filter_map { |node| node["Node Type"] }.uniq.sort,
        indexes: nodes.filter_map { |node| node["Index Name"] }.uniq.sort,
        sequential_scans: nodes
          .select { |node| node["Node Type"] == "Seq Scan" }
          .filter_map { |node| node["Relation Name"] }
          .uniq
          .sort
      }
    end

    def plan_nodes(root)
      nodes = []
      visit = lambda do |node|
        nodes << node
        Array(node["Plans"]).each { |child| visit.call(child) }
      end
      visit.call(root)
      nodes
    end
  end
end

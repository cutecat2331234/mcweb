# frozen_string_literal: true

require "test_helper"

class CommunityQueryPlanAuditTest < ActiveSupport::TestCase
  setup do
    suffix = SecureRandom.hex(5)
    @user = User.create!(
      email: "query-plan-#{suffix}@example.com",
      username: "query_plan_#{suffix}",
      display_name: "Plan marker member",
      password: "password123",
      status: :active
    )
    category = Community::Category.create!(
      name: "Query plan category #{suffix}",
      slug: "query-plan-category-#{suffix}"
    )
    @section = Community::Section.create!(
      category: category,
      name: "Plan marker section",
      slug: "query-plan-section-#{suffix}"
    )
    @topic = Community::Topic.create!(
      section: @section,
      user: @user,
      title: "Plan marker topic",
      status: :published,
      last_posted_at: Time.current
    )
    @post = Community::Post.create!(
      topic: @topic,
      user: @user,
      body: "Plan marker body",
      status: :published,
      post_type: :regular,
      floor_number: 1
    )
    Community::ReadState.create!(
      user: @user,
      topic: @topic,
      last_read_floor: 0
    )
    Community::Tag.create!(
      name: "Plan marker tag",
      slug: "plan-marker-tag-#{suffix}"
    )
    Notification.create!(
      user: @user,
      notification_type: "forum.mention",
      title: "Query plan notification"
    )
  end

  test "audits every production-readiness query family without exposing SQL or search terms" do
    external_search_term = "plan marker private term"
    explain_sql = []
    callback = lambda do |_name, _started, _finished, _unique_id, payload|
      sql = payload[:sql].to_s
      explain_sql << sql if sql.start_with?("EXPLAIN")
    end

    previous_term = ENV["MCWEB_QUERY_AUDIT_TERM"]
    ENV["MCWEB_QUERY_AUDIT_TERM"] = external_search_term
    report = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      Operations::CommunityQueryPlanAudit.call
    end
    names = report.fetch(:queries).pluck(:name)

    assert_equal "PostgreSQL", report.fetch(:adapter)
    assert_equal false, report.fetch(:analyze)
    assert_equal true, report.fetch(:redacted)
    assert_includes names, "full_text.topics"
    assert_includes names, "full_text.posts"
    assert_includes names, "suggest.topics"
    assert_includes names, "top.window"
    assert_includes names, "unread.exists"
    assert_includes names, "notifications.type_aggregate"

    serialized = report.to_json
    assert_not_includes serialized, external_search_term
    assert_not_includes serialized, "plainto_tsquery"
    assert_not_includes serialized, @user.email
    assert_not_includes serialized, @user.username
    assert_predicate explain_sql, :any?
    assert explain_sql.none? { |sql| sql.include?(external_search_term) }
    assert explain_sql.none? { |sql| sql.include?(@user.email) || sql.include?(@user.username) }
    assert explain_sql.none? { |sql| sql.match?(/user_id"?\s*=\s*#{@user.id}\b/) }
  ensure
    if previous_term
      ENV["MCWEB_QUERY_AUDIT_TERM"] = previous_term
    else
      ENV.delete("MCWEB_QUERY_AUDIT_TERM")
    end
  end

  test "critical query indexes are valid and query predicates match their contracts" do
    connection = ActiveRecord::Base.connection
    expected_indexes = %w[
      index_forum_topics_on_title_tsvector
      index_forum_posts_on_body_tsvector
      idx_forum_topics_suggest_title_trgm
      idx_forum_tags_suggest_names_trgm
      idx_users_suggest_names_trgm
      idx_forum_sections_suggest_names_trgm
      idx_forum_posts_top_window
      idx_forum_posts_unread_floor
      idx_notifications_user_created
      idx_notifications_unread_user_created
      idx_notifications_user_type_created
    ]
    expected_indexes.each do |index_name|
      ready = connection.select_value(<<~SQL.squish)
        SELECT index_definition.indisvalid AND index_definition.indisready
        FROM pg_index index_definition
        WHERE index_definition.indexrelid = to_regclass(#{connection.quote(index_name)})
      SQL
      assert_equal true, ready, "#{index_name} must be ready and valid"
    end

    topic_suggest_definition = index_definition("idx_forum_topics_suggest_title_trgm")
    assert_includes topic_suggest_definition, "gin_trgm_ops"
    assert_includes topic_suggest_definition, "status"
    assert_includes topic_suggest_definition, "archived_at IS NULL"

    top_sql = Community::Topic.published_listed.top_ranked(1.week.ago).to_sql
    assert_includes top_sql, "top_window_counts"
    assert_includes top_sql, "GROUP BY"
    assert_not_includes top_sql, "SELECT COUNT(*) FROM forum_posts fp"

    unread_sql = Community::ReadState.with_unread_for(@user).to_sql
    assert_includes unread_sql, "forum_posts.post_type = 'regular'"
    assert_includes unread_sql, "forum_posts.deleted_at IS NULL"
  end

  test "windowed top ranking aggregates qualifying posts once and preserves ranking behavior" do
    second_topic = Community::Topic.create!(
      section: @section,
      user: @user,
      title: "Second topic",
      status: :published,
      last_posted_at: Time.current
    )
    Community::Post.create!(
      topic: @topic,
      user: @user,
      body: "Another recent reply",
      status: :published,
      post_type: :regular,
      floor_number: 2
    )
    Community::Post.create!(
      topic: second_topic,
      user: @user,
      body: "Only post",
      status: :published,
      post_type: :regular,
      floor_number: 1
    )

    ranked_ids = Community::Topic
      .where(id: [ @topic.id, second_topic.id ])
      .top_ranked(1.week.ago)
      .pluck(:id)

    assert_equal [ @topic.id, second_topic.id ], ranked_ids
  end

  test "soft-deleted published posts do not make a topic unread" do
    @post.soft_delete!

    assert_not Community::ReadState
      .with_unread_for(@user)
      .where(forum_topic_id: @topic.id)
      .exists?
  end

  private

  def index_definition(index_name)
    connection = ActiveRecord::Base.connection
    connection.select_value(
      "SELECT pg_get_indexdef(to_regclass(#{connection.quote(index_name)}))"
    )
  end
end

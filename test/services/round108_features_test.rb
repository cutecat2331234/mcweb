# frozen_string_literal: true

require "test_helper"

class Round108LoginRequiredLatestTest < ActionDispatch::IntegrationTest
  setup do
    category = Community::Category.find_or_create_by!(slug: "r108-latest") { |c| c.name = "L" }
    @public_section = Community::Section.find_or_create_by!(category: category, slug: "r108-public") { |s| s.name = "Public"; s.position = 0 }
    @private_section = Community::Section.find_or_create_by!(category: category, slug: "r108-private") { |s| s.name = "Private"; s.position = 1; s.login_required = true }
    @user = create_user
    @public_topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @public_section,
      user: @user,
      title: "Public latest topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    @private_topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @private_section,
      user: @user,
      title: "Private latest topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
  end

  test "latest page hides login required topics from guests" do
    get forum_latest_path
    assert_response :success
    assert_includes response.body, "Public latest topic"
    refute_includes response.body, "Private latest topic"
  end
end

class Round108LoginRequiredSearchPostsTest < ActionDispatch::IntegrationTest
  setup do
    category = Community::Category.find_or_create_by!(slug: "r108-search") { |c| c.name = "S" }
    @public_section = Community::Section.find_or_create_by!(category: category, slug: "r108-search-public") { |s| s.name = "Public"; s.position = 0 }
    @private_section = Community::Section.find_or_create_by!(category: category, slug: "r108-search-private") { |s| s.name = "Private"; s.position = 1; s.login_required = true }
    @user = create_user
    @public_topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @public_section,
      user: @user,
      title: "Public search topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    @private_topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @private_section,
      user: @user,
      title: "Private search topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    Community::Post.create!(topic: @public_topic, user: @user, body: "public searchable body", floor_number: 1, status: "published")
    Community::Post.create!(topic: @private_topic, user: @user, body: "private searchable body", floor_number: 1, status: "published")
  end

  test "search posts excludes login required sections for guests" do
    get forum_search_path(q: "searchable")
    assert_response :success
    assert_includes response.body, "public searchable body"
    refute_includes response.body, "private searchable body"
  end
end

class Round108PostApprovalTest < ActiveSupport::TestCase
  setup do
    SiteSetting.set("forum.require_post_approval_below_tl", "1")
    @user = create_user
    @mod = create_user
    grant_permission(@mod, "forum.users.warn")
    grant_permission(@mod, "forum.topics.lock")
    category = Community::Category.find_or_create_by!(slug: "r108-approval") { |c| c.name = "A" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r108-approval-sec") { |s| s.name = "Sec"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @mod,
      title: "Approval topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @mod,
      replies_count: 0
    )
    Community::Post.create!(topic: @topic, user: @mod, body: "OP", floor_number: 1, status: "published")
  end

  test "low trust user reply requires approval" do
    result = Community::CreatePost.call(user: @user, topic: @topic, body: "Needs review please")
    assert result.success?
    assert_equal "pending_approval", result.value.status
    assert_equal 1, @topic.posts.published.count
  end

  test "moderator can approve pending post" do
    post = Community::Post.create!(
      topic: @topic,
      user: @user,
      floor_number: 2,
      body: "Pending reply",
      status: "pending_approval"
    )
    result = Community::ApprovePost.call(actor: @mod, post: post)
    assert result.success?
    assert_equal "published", post.reload.status
    assert_equal 2, @topic.posts.published.count
  end
end

class Round108TopicAccessibleScopeTest < ActiveSupport::TestCase
  test "accessible_by filters login required sections for guests" do
    category = Community::Category.find_or_create_by!(slug: "r108-scope") { |c| c.name = "Scope" }
    public_section = Community::Section.create!(category: category, name: "Pub", slug: "r108-scope-pub", position: 0)
    private_section = Community::Section.create!(category: category, name: "Priv", slug: "r108-scope-priv", position: 1, login_required: true)
    user = create_user
    public_topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: public_section,
      user: user,
      title: "Visible",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: user,
      replies_count: 0
    )
    Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: private_section,
      user: user,
      title: "Hidden",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: user,
      replies_count: 0
    )

    titles = Community::Topic.published_listed.accessible_by(nil).pluck(:title)
    assert_includes titles, "Visible"
    refute_includes titles, "Hidden"
    assert_includes Community::Topic.published_listed.accessible_by(user).pluck(:title), "Hidden"
  end
end

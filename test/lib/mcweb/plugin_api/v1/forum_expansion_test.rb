# frozen_string_literal: true

require "test_helper"
require "mcweb/plugin_api/v1/forum"

class Mcweb::PluginApi::V1::ForumExpansionTest < ActiveSupport::TestCase
  setup do
    suffix = SecureRandom.hex(5)
    @needle = "pluginneedle#{SecureRandom.alphanumeric(8).downcase}"
    @public_category = Community::Category.create!(
      name: "Plugin public #{suffix}",
      slug: "plugin-public-category-#{suffix}",
      position: 10
    )
    @private_category = Community::Category.create!(
      name: "Plugin private #{suffix}",
      slug: "plugin-private-category-#{suffix}",
      position: 20
    )
    @public_section = Community::Section.create!(
      category: @public_category,
      name: "Plugin public section",
      slug: "plugin-public-section-#{suffix}",
      position: 0
    )
    @private_section = Community::Section.create!(
      category: @private_category,
      name: "Plugin private section",
      slug: "plugin-private-section-#{suffix}",
      position: 0,
      permissions: { "view" => [ "forum.plugin_api.private" ] }
    )
    @author = create_user
    @member = create_user
    @allowed_member = create_user
    grant_permission(@allowed_member, "forum.plugin_api.private")
    grant_permission(@allowed_member, "forum.tags.manage")

    @public_topic, @public_post = create_topic_with_post(
      section: @public_section,
      title: "#{@needle} public topic",
      body: "#{@needle} public post body"
    )
    @private_topic, @private_post = create_topic_with_post(
      section: @private_section,
      title: "#{@needle} private topic",
      body: "#{@needle} private post body"
    )
    Community::Post.create!(
      topic: @public_topic,
      user: @author,
      floor_number: 2,
      body: "#{@needle} staff whisper",
      status: "published",
      post_type: "whisper"
    )

    @public_tag = Community::Tag.create!(
      name: "Plugin public #{suffix}",
      slug: "plugin-public-tag-#{suffix}"
    )
    @staff_tag = Community::Tag.create!(
      name: "Plugin staff #{suffix}",
      slug: "plugin-staff-tag-#{suffix}",
      staff_only: true
    )
    @staff_alias = Community::Tag.create!(
      name: "Plugin staff alias #{suffix}",
      slug: "plugin-staff-alias-#{suffix}",
      canonical_tag: @staff_tag
    )
    Community::TopicTag.create!(topic: @public_topic, tag: @public_tag)

    @audits = []
    @forum = Mcweb::PluginApi::V1::Forum.new(
      capability_auditor: ->(capability) { @audits << capability }
    )
  end

  test "category and tag catalogs expose only resources usable by the reader" do
    categories = @forum.categories(user: @member)
    assert_predicate categories, :success?
    assert_includes categories.value.pluck("id"), @public_category.id
    assert_not_includes categories.value.pluck("id"), @private_category.id

    private_category = @forum.find_category(user: @member, slug: @private_category.slug)
    assert_not_visible private_category

    allowed_category = @forum.find_category(user: @allowed_member, id: @private_category.id)
    assert_predicate allowed_category, :success?
    assert_equal "forum.category", allowed_category.value.fetch("type")

    tags = @forum.tags(user: @member, query: "Plugin")
    assert_includes tags.value.pluck("id"), @public_tag.id
    assert_not_includes tags.value.pluck("id"), @staff_tag.id
    assert_not_includes tags.value.pluck("id"), @staff_alias.id
    assert_not_visible @forum.find_tag(user: @member, slug: @staff_alias.slug)

    staff_alias = @forum.find_tag(user: @allowed_member, slug: @staff_alias.slug)
    assert_predicate staff_alias, :success?
    assert_equal @staff_tag.id, staff_alias.value.fetch("id")
    assert_predicate staff_alias.value, :frozen?
  end

  test "topic and post search preserve aggregate visibility and support catalog filters" do
    topics = @forum.search_topics(user: @member, query: @needle)
    assert_predicate topics, :success?
    assert_includes topics.value.pluck("id"), @public_topic.id
    assert_not_includes topics.value.pluck("id"), @private_topic.id

    tagged = @forum.search_topics(
      user: @member,
      query: @needle,
      tag_slug: @public_tag.slug,
      category_slug: @public_category.slug,
      section_slug: @public_section.slug,
      sort: "relevance"
    )
    assert_equal [ @public_topic.id ], tagged.value.pluck("id")

    posts = @forum.search_posts(user: @member, query: @needle, sort: "oldest")
    assert_predicate posts, :success?
    assert_includes posts.value.pluck("id"), @public_post.id
    assert_not_includes posts.value.pluck("id"), @private_post.id
    assert_equal 1, posts.value.length, "aggregate post search must exclude whispers"

    private_posts = @forum.search_posts(
      user: @member,
      query: @needle,
      category_slug: @private_category.slug
    )
    assert_predicate private_posts, :success?
    assert_empty private_posts.value

    allowed_posts = @forum.search_posts(
      user: @allowed_member,
      query: @needle,
      category_slug: @private_category.slug
    )
    assert_equal [ @private_post.id ], allowed_posts.value.pluck("id")

    invalid = @forum.search_topics(user: @member, query: "", sort: "sideways")
    assert_predicate invalid, :failure?
    assert_equal "invalid_argument", invalid.code
  end

  test "topic and post edits delegate authorization and side effects to core services" do
    edited_topic = @forum.edit_topic(
      user: @author,
      topic_public_id: @public_topic.public_id,
      title: "Edited #{@needle}",
      tag_names: [ @public_tag.name ]
    )
    assert_predicate edited_topic, :success?
    assert_equal "Edited #{@needle}", @public_topic.reload.title
    assert_equal [ @public_tag.id ], @public_topic.tags.pluck(:id)
    assert_equal "forum.topic", edited_topic.value.fetch("type")

    edited_post = @forum.edit_post(
      user: @author,
      id: @public_post.id,
      body: "Edited #{@needle} post body",
      reason: "Plugin test"
    )
    assert_predicate edited_post, :success?
    assert_equal "Edited #{@needle} post body", @public_post.reload.body
    assert_equal "forum.post", edited_post.value.fetch("type")

    denied = @forum.edit_topic(
      user: @member,
      topic_id: @public_topic.id,
      title: "Not allowed"
    )
    assert_predicate denied, :failure?
    assert_equal "service_failure", denied.code

    assert_not_visible @forum.edit_post(
      user: @member,
      id: @private_post.id,
      body: "Must stay private"
    )

    missing_attributes = @forum.edit_topic(
      user: @author,
      topic_id: @public_topic.id
    )
    assert_equal "invalid_argument", missing_attributes.code
  end

  test "reaction reads and writes return stable snapshots while core rules stay authoritative" do
    reaction_types = @forum.reaction_types(user: nil)
    assert_predicate reaction_types, :success?
    assert reaction_types.value.any?
    assert_equal "forum.reaction_type", reaction_types.value.first.fetch("type")
    emoji = reaction_types.value.first.fetch("emoji")

    added = @forum.toggle_reaction(user: @member, post_id: @public_post.id, emoji:)
    assert_predicate added, :success?
    assert added.value.fetch("added")
    assert_equal 1, added.value.fetch("counts").fetch(emoji)

    summary = @forum.post_reactions(user: @member, id: @public_post.id)
    assert_equal [ emoji ], summary.value.fetch("viewer_emojis")
    assert_equal @public_post.id, summary.value.fetch("post_id")

    removed = @forum.toggle_reaction(user: @member, post_id: @public_post.id, emoji:)
    assert_predicate removed, :success?
    refute removed.value.fetch("added")
    assert_equal({}, removed.value.fetch("counts"))

    own_post = @forum.toggle_reaction(user: @author, post_id: @public_post.id, emoji:)
    assert_predicate own_post, :failure?
    assert_equal "service_failure", own_post.code

    assert_not_visible @forum.toggle_reaction(
      user: @member,
      post_id: @private_post.id,
      emoji:
    )
  end

  test "bookmark methods are explicit and idempotent for topics and posts" do
    first = @forum.bookmark_topic(user: @member, topic_id: @public_topic.id)
    second = @forum.bookmark_topic(user: @member, topic_id: @public_topic.id)
    assert_predicate first, :success?
    assert_predicate second, :success?
    assert first.value.fetch("bookmarked")
    assert_equal 1, Community::Bookmark.where(
      user: @member,
      topic: @public_topic,
      post: nil
    ).count

    state = @forum.topic_bookmark(user: @member, topic_public_id: @public_topic.public_id)
    assert state.value.fetch("bookmarked")
    assert_equal "topic", state.value.fetch("resource_type")

    @forum.unbookmark_topic(user: @member, topic_id: @public_topic.id)
    @forum.unbookmark_topic(user: @member, topic_id: @public_topic.id)
    refute @forum.topic_bookmark(user: @member, topic_id: @public_topic.id)
      .value.fetch("bookmarked")

    post_bookmark = @forum.bookmark_post(user: @member, post_id: @public_post.id)
    assert post_bookmark.value.fetch("bookmarked")
    assert_equal "post", post_bookmark.value.fetch("resource_type")
    @forum.unbookmark_post(user: @member, post_id: @public_post.id)
    refute @forum.post_bookmark(user: @member, post_id: @public_post.id)
      .value.fetch("bookmarked")

    assert_not_visible @forum.bookmark_topic(
      user: @member,
      topic_id: @private_topic.id
    )

    invalid = @forum.set_post_bookmark(
      user: @member,
      post_id: @public_post.id,
      bookmarked: "yes"
    )
    assert_equal "invalid_argument", invalid.code
  end

  test "topic section and tag subscriptions expose explicit levels and unsubscribe operations" do
    topic = @forum.subscribe_topic(
      user: @member,
      topic_id: @public_topic.id,
      level: "tracking"
    )
    assert_predicate topic, :success?
    assert_equal "tracking", topic.value.fetch("notification_level")
    assert topic.value.fetch("watching")

    repeated = @forum.subscribe_topic(
      user: @member,
      topic_id: @public_topic.id,
      level: "tracking"
    )
    assert_predicate repeated, :success?
    assert_equal 1, Community::Subscription.where(
      user: @member,
      subscribable: @public_topic
    ).count
    assert_equal "tracking", @forum.topic_subscription(
      user: @member,
      topic_id: @public_topic.id
    ).value.fetch("notification_level")

    @forum.unsubscribe_topic(user: @member, topic_id: @public_topic.id)
    refute @forum.topic_subscription(
      user: @member,
      topic_id: @public_topic.id
    ).value.fetch("watching")

    section = @forum.subscribe_section(
      user: @member,
      section_slug: @public_section.slug,
      level: "normal"
    )
    assert_equal "normal", section.value.fetch("notification_level")
    assert_equal "normal", @forum.section_subscription(
      user: @member,
      section_id: @public_section.id
    ).value.fetch("notification_level")

    tag = @forum.subscribe_tag(
      user: @member,
      tag_slug: @public_tag.slug
    )
    assert_equal "watching", tag.value.fetch("notification_level")
    assert_equal "watching", @forum.tag_subscription(
      user: @member,
      tag_id: @public_tag.id
    ).value.fetch("notification_level")

    invalid = @forum.set_tag_subscription(
      user: @member,
      tag_id: @public_tag.id,
      level: "immediate"
    )
    assert_equal "invalid_argument", invalid.code

    assert_not_visible @forum.subscribe_section(
      user: @member,
      section_id: @private_section.id
    )
    assert_includes @audits, "forum.read"
    assert_includes @audits, "forum.write"
  end

  test "revoking section permission immediately closes catalogs searches state reads and writes" do
    bookmarked = @forum.bookmark_topic(
      user: @allowed_member,
      topic_id: @private_topic.id
    )
    subscribed = @forum.subscribe_topic(
      user: @allowed_member,
      topic_id: @private_topic.id
    )
    assert_predicate bookmarked, :success?
    assert_predicate subscribed, :success?

    private_role = Role.find_by!(key: "test_forum_plugin_api_private")
    @allowed_member.roles.delete(private_role)

    assert_not_visible @forum.find_category(
      user: @allowed_member,
      id: @private_category.id
    )
    assert_not_visible @forum.find_section(
      user: @allowed_member,
      id: @private_section.id
    )
    assert_not_visible @forum.find_topic(
      user: @allowed_member,
      id: @private_topic.id
    )
    assert_not_visible @forum.find_post(
      user: @allowed_member,
      id: @private_post.id
    )
    assert_not_visible @forum.topic_bookmark(
      user: @allowed_member,
      topic_id: @private_topic.id
    )
    assert_not_visible @forum.topic_subscription(
      user: @allowed_member,
      topic_id: @private_topic.id
    )
    assert_not_visible @forum.edit_topic(
      user: @allowed_member,
      topic_id: @private_topic.id,
      title: "Must not change"
    )
    assert_not_visible @forum.edit_post(
      user: @allowed_member,
      id: @private_post.id,
      body: "Must not change"
    )

    categories = @forum.categories(user: @allowed_member)
    assert_not_includes categories.value.pluck("id"), @private_category.id
    assert_empty @forum.search_topics(
      user: @allowed_member,
      query: @needle,
      category_slug: @private_category.slug
    ).value
    assert_empty @forum.search_topics(
      user: @allowed_member,
      query: @needle,
      section_slug: @private_section.slug
    ).value
    assert_empty @forum.search_posts(
      user: @allowed_member,
      query: @needle,
      category_slug: @private_category.slug
    ).value
    assert_empty @forum.search_posts(
      user: @allowed_member,
      query: @needle,
      section_slug: @private_section.slug
    ).value

    assert Community::Bookmark.exists?(
      user: @allowed_member,
      topic: @private_topic,
      post: nil
    )
    assert Community::Subscription.exists?(
      user: @allowed_member,
      subscribable: @private_topic
    )

    grant_permission(@allowed_member, "forum.plugin_api.private")
    assert @forum.topic_bookmark(
      user: @allowed_member,
      topic_id: @private_topic.id
    ).value.fetch("bookmarked")
    assert @forum.topic_subscription(
      user: @allowed_member,
      topic_id: @private_topic.id
    ).value.fetch("watching")
  end

  test "selectors and bounded arguments fail uniformly before any record is exposed" do
    invalid_results = [
      @forum.find_category(
        user: @member,
        id: @public_category.id,
        slug: @public_category.slug
      ),
      @forum.find_section(user: @member),
      @forum.find_tag(user: @member, id: 0),
      @forum.find_topic(
        user: @member,
        id: @public_topic.id,
        public_id: @public_topic.public_id
      ),
      @forum.posts(user: @member),
      @forum.edit_topic(
        user: @author,
        topic_id: @public_topic.id,
        topic_public_id: @public_topic.public_id,
        title: "Invalid selector"
      ),
      @forum.set_topic_bookmark(
        user: @member,
        topic_id: @public_topic.id,
        topic_public_id: @public_topic.public_id,
        bookmarked: true
      ),
      @forum.set_section_subscription(
        user: @member,
        section_id: @public_section.id,
        section_slug: @public_section.slug,
        level: "watching"
      ),
      @forum.search_topics(
        user: @member,
        query: @needle,
        tag_slug: "x" * (Mcweb::PluginApi::V1::Forum::MAX_FILTER_LENGTH + 1)
      ),
      @forum.search_posts(
        user: @member,
        query: "x" * (Mcweb::PluginApi::V1::Forum::MAX_SEARCH_LENGTH + 1)
      )
    ]

    invalid_results.each do |result|
      assert_predicate result, :failure?
      assert_equal "invalid_argument", result.code
      assert_predicate result, :frozen?
    end
  end

  test "every expanded operation audits its documented capability exactly once" do
    audits = []
    forum = Mcweb::PluginApi::V1::Forum.new(
      capability_auditor: ->(capability) { audits << capability }
    )
    invalid_user = Object.new

    read_operations = [
      -> { forum.find_category(user: invalid_user, id: 1) },
      -> { forum.categories(user: invalid_user) },
      -> { forum.find_tag(user: invalid_user, id: 1) },
      -> { forum.tags(user: invalid_user) },
      -> { forum.search_topics(user: invalid_user, query: "query") },
      -> { forum.search_posts(user: invalid_user, query: "query") },
      -> { forum.reaction_types(user: invalid_user) },
      -> { forum.post_reactions(user: invalid_user, id: 1) },
      -> { forum.topic_bookmark(user: invalid_user, topic_id: 1) },
      -> { forum.post_bookmark(user: invalid_user, post_id: 1) },
      -> { forum.topic_subscription(user: invalid_user, topic_id: 1) },
      -> { forum.section_subscription(user: invalid_user, section_id: 1) },
      -> { forum.tag_subscription(user: invalid_user, tag_id: 1) }
    ]
    write_operations = [
      -> { forum.edit_topic(user: invalid_user, topic_id: 1, title: "Title") },
      -> { forum.edit_post(user: invalid_user, id: 1, body: "Body") },
      -> { forum.toggle_reaction(user: invalid_user, post_id: 1, emoji: "x") },
      -> { forum.set_topic_bookmark(user: invalid_user, topic_id: 1, bookmarked: true) },
      -> { forum.bookmark_topic(user: invalid_user, topic_id: 1) },
      -> { forum.unbookmark_topic(user: invalid_user, topic_id: 1) },
      -> { forum.set_post_bookmark(user: invalid_user, post_id: 1, bookmarked: true) },
      -> { forum.bookmark_post(user: invalid_user, post_id: 1) },
      -> { forum.unbookmark_post(user: invalid_user, post_id: 1) },
      -> { forum.set_topic_subscription(user: invalid_user, topic_id: 1, level: "watching") },
      -> { forum.subscribe_topic(user: invalid_user, topic_id: 1) },
      -> { forum.unsubscribe_topic(user: invalid_user, topic_id: 1) },
      -> { forum.set_section_subscription(user: invalid_user, section_id: 1, level: "watching") },
      -> { forum.subscribe_section(user: invalid_user, section_id: 1) },
      -> { forum.unsubscribe_section(user: invalid_user, section_id: 1) },
      -> { forum.set_tag_subscription(user: invalid_user, tag_id: 1, level: "watching") },
      -> { forum.subscribe_tag(user: invalid_user, tag_id: 1) },
      -> { forum.unsubscribe_tag(user: invalid_user, tag_id: 1) }
    ]

    {
      "forum.read" => read_operations,
      "forum.write" => write_operations
    }.each do |capability, operations|
      operations.each do |operation|
        audits.clear
        result = operation.call
        assert_predicate result, :failure?
        assert_equal "invalid_user", result.code
        assert_equal [ capability ], audits
      end
    end
  end

  test "new catalog interaction and state snapshots are deeply immutable model-free values" do
    emoji = @forum.reaction_types(user: @member).value.first.fetch("emoji")
    @forum.toggle_reaction(user: @member, post_id: @public_post.id, emoji:)
    @forum.bookmark_topic(user: @member, topic_id: @public_topic.id)
    @forum.subscribe_tag(user: @member, tag_id: @public_tag.id)

    results = [
      @forum.find_category(user: @member, id: @public_category.id),
      @forum.find_tag(user: @member, id: @public_tag.id),
      @forum.search_topics(user: @member, query: @needle),
      @forum.reaction_types(user: @member),
      @forum.post_reactions(user: @member, id: @public_post.id),
      @forum.topic_bookmark(user: @member, topic_id: @public_topic.id),
      @forum.tag_subscription(user: @member, tag_id: @public_tag.id)
    ]

    results.each do |result|
      assert_predicate result, :success?
      assert_deeply_frozen(result.to_h)
      refute_contains_active_record(result.to_h)
    end
    assert_raises(FrozenError) do
      results[4].value.fetch("counts")[emoji] = 100
    end
    assert_raises(FrozenError) do
      results[2].value << { "id" => -1 }
    end
  end

  private

  def create_topic_with_post(section:, title:, body:)
    topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section:,
      user: @author,
      title:,
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    post = Community::Post.create!(
      topic:,
      user: @author,
      floor_number: 1,
      body:,
      status: "published"
    )
    [ topic, post ]
  end

  def assert_not_visible(result)
    assert_predicate result, :failure?
    assert_equal "not_found", result.code
    assert_match(/not found or not visible/, result.error)
  end

  def assert_deeply_frozen(value)
    assert_predicate value, :frozen?
    case value
    when Hash
      value.each do |key, item|
        assert_predicate key, :frozen?
        assert_deeply_frozen(item)
      end
    when Array
      value.each { |item| assert_deeply_frozen(item) }
    end
  end

  def refute_contains_active_record(value)
    refute_kind_of ActiveRecord::Base, value
    case value
    when Hash
      value.each do |key, item|
        refute_contains_active_record(key)
        refute_contains_active_record(item)
      end
    when Array
      value.each { |item| refute_contains_active_record(item) }
    end
  end
end

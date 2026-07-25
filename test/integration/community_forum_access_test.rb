# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class CommunityForumAccessTest < ActionDispatch::IntegrationTest
  setup do
    suffix = SecureRandom.hex(4)
    category = Community::Category.create!(
      name: "Private category #{suffix}",
      slug: "private-category-#{suffix}"
    )
    @section = Community::Section.create!(
      category: category,
      name: "Permission-only section #{suffix}",
      slug: "permission-only-#{suffix}",
      position: 0,
      permissions: { "view" => [ "forum.web_private.view" ] }
    )
    @public_section = Community::Section.create!(
      category: category,
      name: "Public access section #{suffix}",
      slug: "public-access-#{suffix}",
      position: 1
    )
    @author = create_user
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @author,
      title: "Permission-only topic #{suffix}",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    Community::Post.create!(
      topic: @topic,
      user: @author,
      floor_number: 1,
      body: "Permission-only body #{suffix}",
      status: "published"
    )
  end

  test "guest gets not found for a permission-only section" do
    get forum_section_path(@section)

    assert_response :not_found
  end

  test "signed-in member without permission cannot read section or topic" do
    sign_in_as(create_user)

    get forum_section_path(@section)
    assert_response :not_found

    get forum_topic_path(@topic)
    assert_response :not_found
  end

  test "signed-in member without permission does not see topic in forum lists" do
    sign_in_as(create_user)

    get forum_latest_path
    assert_response :success
    assert_not_includes response.body, @topic.title

    get forum_sections_path
    assert_response :success
    assert_not_includes response.body, @section.name
    assert_not_includes response.body, @topic.title
  end

  test "shared global announcements obey section access and listed state" do
    @topic.update!(global_announcement: true)
    archived_marker = "Archived featured announcement #{SecureRandom.hex(5)}"
    archived, = create_public_topic_with_post(
      status: "published",
      archived_at: Time.current
    )
    archived.update!(
      title: archived_marker,
      global_announcement: true,
      featured: true
    )

    get forum_latest_path

    assert_response :success
    announcements = Array(inertia.props.deep_symbolize_keys[:global_announcements])
    ids = announcements.pluck(:id)
    assert_not_includes ids, @topic.public_id
    assert_not_includes ids, archived.public_id

    get forum_section_path(@public_section)
    assert_response :success
    assert_not_includes response.body, archived_marker
  end

  test "personal aggregate pages and notifications do not reveal inaccessible topics" do
    marker = "Restricted personal surface #{SecureRandom.hex(5)}"
    @topic.update!(title: marker)
    member = create_user
    @topic.update!(assigned_to: member)
    Community::UserFollow.create!(follower: member, followed: @author)
    Community::Subscription.create!(user: member, subscribable: @topic)
    tag = Community::Tag.create!(
      name: "restricted-personal-#{SecureRandom.hex(4)}",
      slug: "restricted-personal-#{SecureRandom.hex(4)}"
    )
    Community::TopicTag.create!(topic: @topic, tag: tag)
    Community::Subscription.create!(user: member, subscribable: tag)
    Notification.create!(
      user: member,
      notification_type: "forum.topic_reply",
      title: marker,
      body: "#{marker} body",
      metadata: {
        "topic_id" => @topic.public_id,
        "path" => forum_topic_path(@topic)
      }
    )
    sign_in_as(member)

    [
      forum_following_path,
      forum_watching_path,
      forum_watched_tag_topics_path,
      forum_assigned_path,
      forum_notifications_path
    ].each do |path|
      get path
      assert_response :success
      assert_not_includes response.body, marker, "#{path} exposed an inaccessible topic"
    end
  end

  test "staff-only tags stay hidden across search RSS and stale subscriptions" do
    topic, = create_public_topic_with_post(status: "published")
    needle = "tagprivacy#{SecureRandom.hex(5)}"
    topic.update!(title: "Hidden tag association #{needle}")
    staff_tag = Community::Tag.create!(
      name: "Confidential tag #{SecureRandom.hex(5)}",
      slug: "confidential-tag-#{SecureRandom.hex(5)}",
      staff_only: true
    )
    Community::TopicTag.create!(topic: topic, tag: staff_tag)

    member = create_user
    Community::Subscription.create!(user: member, subscribable: staff_tag)
    search = member.forum_saved_searches.create!(
      name: "Stale staff tag search",
      query: needle,
      filters: { tag: staff_tag.slug }
    )
    sign_in_as(member)

    get forum_watched_tag_topics_path
    assert_response :success
    assert_not_includes response.body, topic.title

    get forum_watching_opml_path(token: Community::WatchingOpmlToken.generate(member))
    assert_response :success
    assert_not_includes response.body, staff_tag.name

    get forum_tag_rss_path(slug: staff_tag.slug)
    assert_response :not_found

    get forum_search_path(q: needle, tag: staff_tag.slug)
    assert_response :success
    assert_not_includes response.body, topic.title
    assert_not_includes response.body, staff_tag.name

    get forum_saved_search_rss_path(
      id: search.id,
      token: Community::SavedSearchRssToken.generate(search)
    )
    assert_response :success
    assert_not_includes response.body, topic.title
    assert_not_includes response.body, staff_tag.name

    grant_permission(member, "forum.tags.manage")

    get forum_tag_rss_path(slug: staff_tag.slug)
    assert_response :success
    assert_includes response.body, topic.title
  end

  test "member with view permission can read section and topic" do
    member = create_user
    grant_permission(member, "forum.web_private.view")
    sign_in_as(member)

    get forum_section_path(@section)
    assert_response :success
    assert_includes response.body, @topic.title

    get forum_topic_path(@topic)
    assert_response :success
  end

  test "raw post is unavailable through a hidden topic" do
    _topic, post = create_public_topic_with_post(status: "hidden")

    get raw_forum_post_path(post)

    assert_response :not_found
  end

  test "raw post is unavailable through a draft topic" do
    _topic, post = create_public_topic_with_post(status: "draft")

    get raw_forum_post_path(post)

    assert_response :not_found
  end

  test "raw post is unavailable through an archived topic" do
    _topic, post = create_public_topic_with_post(
      status: "published",
      archived_at: Time.current
    )

    get raw_forum_post_path(post)

    assert_response :not_found
  end

  test "unlisted topic and its raw post stay readable by direct link" do
    topic, post = create_public_topic_with_post(
      status: "published",
      unlisted: true
    )

    get forum_topic_path(topic)
    assert_response :success

    get raw_forum_post_path(post)
    assert_response :success
    assert_includes response.body, post.body
  end

  test "section moderator can read hidden topic pending post and whisper" do
    topic, pending_post = create_public_topic_with_post(
      status: "hidden",
      post_status: "pending_approval"
    )
    whisper = Community::Post.create!(
      topic: topic,
      user: @author,
      floor_number: 2,
      body: "Section moderator whisper",
      status: "published",
      post_type: "whisper"
    )
    moderator = create_user
    Community::SectionModerator.create!(section: @public_section, user: moderator)
    sign_in_as(moderator)

    get forum_topic_path(topic)
    assert_response :success
    assert_includes response.body, pending_post.body
    assert_includes response.body, whisper.body

    get raw_forum_post_path(pending_post)
    assert_response :success

    get raw_forum_post_path(whisper)
    assert_response :success
  end

  test "public aggregate endpoints exclude whispers moderation states and non-listed topics" do
    suffix = SecureRandom.hex(4)
    topic, regular = create_public_topic_with_post(status: "published")
    regular.update!(body: "Public aggregate #{suffix}")
    whisper = create_post(
      topic: topic,
      floor: 2,
      body: "Whisper aggregate #{suffix}",
      status: "published",
      post_type: "whisper"
    )
    pending = create_post(
      topic: topic,
      floor: 3,
      body: "Pending aggregate #{suffix}",
      status: "pending_approval"
    )
    hidden = create_post(
      topic: topic,
      floor: 4,
      body: "Hidden aggregate #{suffix}",
      status: "hidden"
    )

    unlisted_topic, unlisted_post = create_public_topic_with_post(
      status: "published",
      unlisted: true
    )
    unlisted_topic.update!(title: "Unlisted aggregate #{suffix}")
    unlisted_post.update!(body: "Unlisted aggregate body #{suffix}")

    archived_topic, archived_post = create_public_topic_with_post(
      status: "published",
      archived_at: Time.current
    )
    archived_topic.update!(title: "Archived aggregate #{suffix}")
    archived_post.update!(body: "Archived aggregate body #{suffix}")

    hidden_topic, hidden_topic_post = create_public_topic_with_post(status: "hidden")
    hidden_topic.update!(title: "Hidden topic aggregate #{suffix}")
    hidden_topic_post.update!(body: "Hidden topic aggregate body #{suffix}")

    [ regular, whisper, pending, hidden, unlisted_post, archived_post, hidden_topic_post ].each do |post|
      Community::Reaction.create!(post: post, user: create_user, emoji: "like")
    end

    get card_forum_user_path(@author.username), as: :json
    assert_response :success
    card = JSON.parse(response.body)
    assert_equal 1, card["posts_count"]
    assert_equal 1, card["likes_received"]
    assert_equal 1, card["reaction_score"]

    get forum_user_path(@author.username)
    assert_response :success
    profile_props = inertia.props.deep_symbolize_keys
    assert_equal 1, profile_props.dig(:profile, :posts_count)
    assert_equal [ regular.id ], profile_props[:recent_posts].map { |post| post[:id] }
    assert_equal [ regular.id ], profile_props[:liked_posts].map { |post| post[:id] }
    assert_not_includes profile_props[:topics].map { |item| item[:id] }, unlisted_topic.public_id
    assert_not_includes profile_props[:topics].map { |item| item[:id] }, archived_topic.public_id
    assert_not_includes response.body, "Whisper aggregate #{suffix}"
    assert_not_includes response.body, "Pending aggregate #{suffix}"
    assert_not_includes response.body, "Hidden aggregate #{suffix}"

    get forum_activity_path(tab: "posts")
    assert_response :success
    activity_ids = inertia.props.deep_symbolize_keys[:posts].map { |post| post[:id] }
    assert_includes activity_ids, regular.id
    assert_not_includes activity_ids, whisper.id
    assert_not_includes activity_ids, pending.id
    assert_not_includes activity_ids, hidden.id

    get forum_search_path(q: "Whisper aggregate #{suffix}", posts_only: "1")
    assert_response :success
    assert_empty inertia.props.deep_symbolize_keys[:posts]

    get forum_members_path(q: @author.username, sort: "posts")
    assert_response :success
    member = inertia.props.deep_symbolize_keys[:members].find { |item| item[:username] == @author.username }
    assert_equal 1, member[:posts_count]

    get forum_leaderboard_path(metric: "posts")
    assert_response :success
    entry = inertia.props.deep_symbolize_keys[:entries].find { |item| item[:username] == @author.username }
    assert_equal 1, entry[:score]

    get forum_statistics_path
    assert_response :success
    top_poster = inertia.props.deep_symbolize_keys[:topPosters].find { |item| item[:username] == @author.username }
    assert_equal 1, top_poster[:value]
  end

  test "feeds and bookmarks never serialize a published whisper" do
    suffix = SecureRandom.hex(4)
    topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @public_section,
      user: @author,
      title: "Whisper-only feed #{suffix}",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    whisper = create_post(
      topic: topic,
      floor: 1,
      body: "Whisper-only feed body #{suffix}",
      status: "published",
      post_type: "whisper"
    )

    get forum_latest_rss_path
    assert_response :success
    assert_includes response.body, topic.title
    assert_not_includes response.body, whisper.body

    member = create_user
    Community::Bookmark.create!(user: member, topic: topic, post: whisper)
    sign_in_as(member)
    get forum_bookmarks_path
    assert_response :success
    assert_not_includes response.body, whisper.body
    assert_empty inertia.props.deep_symbolize_keys[:postBookmarks]
  end

  test "topic list metadata excludes whisper participants and restricted related topics" do
    topic, = create_public_topic_with_post(status: "published")
    whisperer = create_user
    Community::Post.create!(
      topic: topic,
      user: whisperer,
      floor_number: 2,
      body: "Participant whisper",
      status: "published",
      post_type: "whisper"
    )
    tag = Community::Tag.create!(
      name: "privacy-related-#{SecureRandom.hex(4)}",
      slug: "privacy-related-#{SecureRandom.hex(4)}"
    )
    Community::TopicTag.create!(topic: topic, tag: tag)
    Community::TopicTag.create!(topic: @topic, tag: tag)

    get forum_latest_path
    assert_response :success
    listed_topic = inertia.props.deep_symbolize_keys[:topics].find { |item| item[:id] == topic.public_id }
    participant_names = listed_topic[:participant_avatars].map { |participant| participant[:username] }
    assert_not_includes participant_names, whisperer.username

    get forum_topic_path(topic)
    assert_response :success
    related_ids = inertia.props.deep_symbolize_keys[:relatedTopics].map { |item| item[:id] }
    assert_not_includes related_ids, @topic.public_id
  end

  private

  def create_post(topic:, floor:, body:, status:, post_type: "regular")
    Community::Post.create!(
      topic: topic,
      user: @author,
      floor_number: floor,
      body: body,
      status: status,
      post_type: post_type
    )
  end

  def create_public_topic_with_post(status:, archived_at: nil, unlisted: false, post_status: "published")
    suffix = SecureRandom.hex(4)
    topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @public_section,
      user: @author,
      title: "Policy state topic #{suffix}",
      status: status,
      archived_at: archived_at,
      unlisted: unlisted,
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    post = Community::Post.create!(
      topic: topic,
      user: @author,
      floor_number: 1,
      body: "Policy state body #{suffix}",
      status: post_status
    )
    [ topic, post ]
  end
end

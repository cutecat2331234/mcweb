# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class CommunityNewTest < ActionDispatch::IntegrationTest
  setup do
    @viewer = create_user
    @author = create_user
    category = Community::Category.create!(name: "C", slug: "c-#{SecureRandom.hex(3)}")
    @section = Community::Section.create!(category: category, name: "S", slug: "s-#{SecureRandom.hex(3)}", position: 0)
  end

  test "guests are redirected to sign in" do
    get forum_new_feed_path
    assert_response :redirect
  end

  test "lists recent topics the viewer has not opened" do
    fresh = seed_topic(title: "fresh")
    sign_in_as(@viewer)

    get forum_new_feed_path
    assert_response :success
    assert_inertia_component "Community/New/Index"

    props = inertia.props.deep_symbolize_keys
    ids = props[:topics].map { |topic| topic[:id] }
    assert_includes ids, fresh.public_id
    assert_equal 14, props[:windowDays]
  end

  test "shares an unseen-new count for the nav badge" do
    seed_topic(title: "n1")
    seed_topic(title: "n2")
    read = seed_topic(title: "read")
    Community::ReadState.create!(user: @viewer, forum_topic_id: read.id, last_read_floor: 1)
    sign_in_as(@viewer)

    get forum_new_feed_path
    assert_equal 2, inertia.props.deep_symbolize_keys[:forum_new][:count]
  end

  test "excludes topics the viewer has already read" do
    seen = seed_topic(title: "seen")
    Community::ReadState.create!(user: @viewer, forum_topic_id: seen.id, last_read_floor: 1)
    sign_in_as(@viewer)

    get forum_new_feed_path
    ids = inertia.props.deep_symbolize_keys[:topics].map { |topic| topic[:id] }
    assert_not_includes ids, seen.public_id
  end

  test "excludes topics older than the window" do
    old = seed_topic(title: "old", created_at: 30.days.ago)
    sign_in_as(@viewer)

    get forum_new_feed_path
    ids = inertia.props.deep_symbolize_keys[:topics].map { |topic| topic[:id] }
    assert_not_includes ids, old.public_id
  end

  test "excludes muted topics and topics in muted sections" do
    muted_topic = seed_topic(title: "muted-topic")
    Community::TopicMute.create!(user: @viewer, forum_topic_id: muted_topic.id)

    muted_category = Community::Category.create!(name: "MC", slug: "mc-#{SecureRandom.hex(3)}")
    muted_section = Community::Section.create!(category: muted_category, name: "MS", slug: "ms-#{SecureRandom.hex(3)}", position: 1)
    in_muted_section = seed_topic(title: "in-muted-section", section: muted_section)
    Community::SectionMute.create!(user: @viewer, forum_section_id: muted_section.id)

    sign_in_as(@viewer)
    get forum_new_feed_path
    ids = inertia.props.deep_symbolize_keys[:topics].map { |topic| topic[:id] }
    assert_not_includes ids, muted_topic.public_id
    assert_not_includes ids, in_muted_section.public_id
  end

  test "dismiss marks all current new topics as seen" do
    a = seed_topic(title: "a")
    b = seed_topic(title: "b")
    sign_in_as(@viewer)

    assert_difference -> { Community::ReadState.where(user: @viewer).count }, 2 do
      post forum_dismiss_new_feed_path
    end
    assert_response :redirect

    get forum_new_feed_path
    ids = inertia.props.deep_symbolize_keys[:topics].map { |topic| topic[:id] }
    assert_not_includes ids, a.public_id
    assert_not_includes ids, b.public_id
  end

  test "dismiss respects the active filter" do
    wiki = seed_topic(title: "wiki", wiki: true)
    normal = seed_topic(title: "normal")
    sign_in_as(@viewer)

    post forum_dismiss_new_feed_path(filter: "wiki")
    assert_response :redirect

    assert Community::ReadState.exists?(user: @viewer, forum_topic_id: wiki.id)
    assert_not Community::ReadState.exists?(user: @viewer, forum_topic_id: normal.id)
  end

  private

  def seed_topic(title: "T", section: @section, created_at: Time.current, wiki: false)
    topic = Community::Topic.create!(
      public_id: "t_#{SecureRandom.alphanumeric(10)}",
      section: section, user: @author, title: title, status: "published",
      created_at: created_at, last_posted_at: created_at, last_post_user: @author,
      replies_count: 0, wiki: wiki
    )
    Community::Post.create!(
      topic: topic, user: @author, floor_number: 1,
      body: "opening post", status: "published", created_at: created_at
    )
    topic
  end
end

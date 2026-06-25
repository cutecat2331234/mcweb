# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class CommunityTopTest < ActionDispatch::IntegrationTest
  setup do
    @author = create_user
    category = Community::Category.create!(name: "C", slug: "c-#{SecureRandom.hex(3)}")
    @section = Community::Section.create!(category: category, name: "S", slug: "s-#{SecureRandom.hex(3)}", position: 0)
  end

  test "renders the Top page with period options and defaults to week" do
    seed_topic(replies_in_window: 1)

    get forum_top_path
    assert_response :success
    assert_inertia_component "Community/Top/Index"

    props = inertia.props.deep_symbolize_keys
    assert_equal "week", props[:period]
    assert_equal %w[today week month quarter year all], props[:periodOptions].map { |o| o[:value] }
  end

  test "invalid period falls back to the default" do
    seed_topic(replies_in_window: 1)
    get forum_top_path(period: "bogus")
    assert_response :success
    assert_equal "week", inertia.props.deep_symbolize_keys[:period]
  end

  test "ranks topics by number of posts in the window" do
    quiet = seed_topic(title: "quiet", replies_in_window: 1)
    busy = seed_topic(title: "busy", replies_in_window: 4)

    get forum_top_path(period: "week")
    assert_response :success

    ids = inertia.props.deep_symbolize_keys[:topics].map { |topic| topic[:id] }
    mine = ids.select { |id| [ busy.public_id, quiet.public_id ].include?(id) }
    assert_equal [ busy.public_id, quiet.public_id ], mine
  end

  test "excludes topics with no posts inside the window" do
    fresh = seed_topic(title: "fresh", replies_in_window: 2)
    stale = seed_topic(title: "stale", replies_in_window: 0)
    # stale's opening post + replies are all old
    Community::Post.where(forum_topic_id: stale.id).update_all(created_at: 40.days.ago)

    get forum_top_path(period: "month")
    assert_response :success

    ids = inertia.props.deep_symbolize_keys[:topics].map { |topic| topic[:id] }
    assert_includes ids, fresh.public_id
    assert_not_includes ids, stale.public_id
  end

  test "all-time period includes topics regardless of recency and ranks by engagement" do
    big = seed_topic(title: "big", replies_in_window: 0, replies_count: 50, views_count: 10)
    small = seed_topic(title: "small", replies_in_window: 0, replies_count: 1, views_count: 1)
    Community::Post.update_all(created_at: 2.years.ago)

    get forum_top_path(period: "all")
    assert_response :success

    ids = inertia.props.deep_symbolize_keys[:topics].map { |topic| topic[:id] }
    mine = ids.select { |id| [ big.public_id, small.public_id ].include?(id) }
    assert_equal [ big.public_id, small.public_id ], mine
  end

  test "hides topics from login-required sections for guests" do
    private_category = Community::Category.create!(name: "P", slug: "p-#{SecureRandom.hex(3)}")
    private_section = Community::Section.create!(category: private_category, name: "PS", slug: "ps-#{SecureRandom.hex(3)}", position: 1, login_required: true)
    hidden = seed_topic(title: "secret", section: private_section, replies_in_window: 3)

    get forum_top_path(period: "week")
    assert_response :success

    ids = inertia.props.deep_symbolize_keys[:topics].map { |topic| topic[:id] }
    assert_not_includes ids, hidden.public_id
  end

  test "whisper and small_action posts do not inflate the Top ranking" do
    # chatty: more genuine (regular) engagement.
    chatty = seed_topic(title: "chatty", replies_in_window: 3)
    # quiet: fewer regular replies, but padded with whispers/system actions so it
    # has MORE total posts. Without excluding non-regular posts it would rank first.
    quiet = seed_topic(title: "quiet", replies_in_window: 1)
    next_floor = quiet.posts.maximum(:floor_number).to_i
    %w[whisper whisper whisper small_action small_action].each_with_index do |type, i|
      Community::Post.create!(topic: quiet, user: @author, floor_number: next_floor + i + 1, body: "x#{i}", status: "published", post_type: type)
    end

    get forum_top_path(period: "week")
    ids = inertia.props.deep_symbolize_keys[:topics].map { |topic| topic[:id] }
    mine = ids.select { |id| [ chatty.public_id, quiet.public_id ].include?(id) }
    # chatty (4 regular) outranks quiet (2 regular) despite quiet's larger total post count
    assert_equal [ chatty.public_id, quiet.public_id ], mine
  end

  test "RSS feed hides login-required sections from guests" do
    private_category = Community::Category.create!(name: "P", slug: "p-#{SecureRandom.hex(3)}")
    private_section = Community::Section.create!(category: private_category, name: "PS", slug: "ps-#{SecureRandom.hex(3)}", position: 9, login_required: true)
    hidden = seed_topic(title: "secret-feed", section: private_section, replies_in_window: 3)

    get forum_top_rss_path(period: "week")
    assert_response :success
    assert_not_includes response.body, hidden.public_id
  end

  test "exposes a period-scoped RSS feed" do
    topic = seed_topic(title: "feed-topic", replies_in_window: 2)

    get forum_top_rss_path(period: "week")
    assert_response :success
    assert_match %r{application/rss\+xml}, response.media_type
    assert_includes response.body, "feed-topic"
    assert_includes response.body, topic.public_id
  end

  test "the Top page exposes its RSS url for the active period" do
    seed_topic(replies_in_window: 1)
    get forum_top_path(period: "month")
    assert_response :success
    assert_includes inertia.props.deep_symbolize_keys[:rss_url], "period=month"
  end

  private

  def seed_topic(title: "T", section: @section, replies_in_window: 0, replies_count: nil, views_count: 0)
    topic = Community::Topic.create!(
      public_id: "t_#{SecureRandom.alphanumeric(10)}",
      section: section, user: @author, title: title, status: "published",
      last_posted_at: Time.current, last_post_user: @author,
      replies_count: replies_count || replies_in_window, views_count: views_count
    )
    # opening post (floor 1) + replies, all created "now" (inside the window)
    (replies_in_window + 1).times do |i|
      Community::Post.create!(
        topic: topic, user: @author, floor_number: i + 1,
        body: "post #{i}", status: "published"
      )
    end
    topic
  end
end

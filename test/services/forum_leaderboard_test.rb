# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class ForumLeaderboardTest < ActionDispatch::IntegrationTest
  setup do
    @u1 = create_user
    @u2 = create_user
    @u3 = create_user
    category = Community::Category.create!(name: "C", slug: "c-#{SecureRandom.hex(3)}")
    @section = Community::Section.create!(category: category, name: "S", slug: "s-#{SecureRandom.hex(3)}", position: 0)
    seed_posts(@u1, 5)
    seed_posts(@u2, 3)
    seed_posts(@u3, 1)
  end

  test "ranks users by published post count" do
    get forum_leaderboard_path
    assert_response :success
    assert_inertia_component "Community/Leaderboard/Index"

    entries = inertia.props.deep_symbolize_keys[:entries]
    assert_equal [ @u1.username, @u2.username, @u3.username ], entries.map { |e| e[:username] }.first(3)
    assert_equal 1, entries.first[:rank]
    assert_equal 5, entries.first[:score]
  end

  test "week period excludes posts outside the window" do
    Community::Post.where(user: @u1).update_all(created_at: 2.weeks.ago)
    get forum_leaderboard_path(period: "week")
    assert_response :success

    usernames = inertia.props.deep_symbolize_keys[:entries].map { |e| e[:username] }
    assert_equal @u2.username, usernames.first
    assert_not_includes usernames, @u1.username
  end

  private

  def seed_posts(user, count)
    topic = Community::Topic.create!(
      public_id: "t_#{SecureRandom.alphanumeric(10)}",
      section: @section, user: user, title: "T", status: "published",
      last_posted_at: Time.current, last_post_user: user, replies_count: 0
    )
    count.times do |i|
      Community::Post.create!(topic: topic, user: user, floor_number: i + 1, body: "p#{i}", status: "published")
    end
  end
end

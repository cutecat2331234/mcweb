# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class LeaderboardScoreTest < ActionDispatch::IntegrationTest
  setup do
    SiteSetting.set("forum.reaction_scores", "❤️:5")
    @a = create_user
    @b = create_user
    category = Community::Category.create!(name: "C", slug: "c-#{SecureRandom.hex(3)}")
    @section = Community::Section.create!(category: category, name: "S", slug: "s-#{SecureRandom.hex(3)}", position: 0)
    post_a = make_post(@a)
    post_b = make_post(@b)
    # A receives three 👍 (raw count 3, weighted score 3); B receives one ❤️ (weighted score 5).
    3.times { Community::Reaction.create!(user: create_user, post: post_a, emoji: "👍") }
    Community::Reaction.create!(user: create_user, post: post_b, emoji: "❤️")
  end

  def make_post(user)
    topic = Community::Topic.create!(
      public_id: "t_#{SecureRandom.alphanumeric(10)}",
      section: @section, user: user, title: "T", status: "published",
      last_posted_at: Time.current, last_post_user: user, replies_count: 0
    )
    Community::Post.create!(topic: topic, user: user, floor_number: 1, body: "b", status: "published")
  end

  test "score metric ranks by weighted reaction score, not raw count" do
    get forum_leaderboard_path(metric: "score")
    assert_response :success

    usernames = inertia.props.deep_symbolize_keys[:entries].map { |e| e[:username] }
    assert_equal @b.username, usernames.first
    assert_operator usernames.index(@b.username), :<, usernames.index(@a.username)
  end

  test "likes metric still ranks by raw reaction count" do
    get forum_leaderboard_path(metric: "likes")
    assert_response :success

    usernames = inertia.props.deep_symbolize_keys[:entries].map { |e| e[:username] }
    assert_operator usernames.index(@a.username), :<, usernames.index(@b.username)
  end
end

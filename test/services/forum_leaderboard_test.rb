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

  test "week points ranks by points earned inside the window only" do
    sign_in_private_viewer
    award_points(@u1, 10)
    award_points(@u1, 7, at: 2.weeks.ago)
    award_points(@u2, 4, at: 2.weeks.ago)

    get forum_leaderboard_path(period: "week", metric: "points")
    assert_response :success
    assert_inertia_component "Community/Leaderboard/Index"

    scores = points_scores
    assert_equal 10, scores[@u1.username], "only the in-window transaction counts"
    assert_not_includes scores.keys, @u2.username
  end

  test "all points ranks by lifetime balance including old transactions" do
    sign_in_private_viewer
    award_points(@u1, 10)
    award_points(@u1, 7, at: 2.weeks.ago)
    award_points(@u2, 4, at: 2.weeks.ago)

    get forum_leaderboard_path(period: "all", metric: "points")
    assert_response :success

    scores = points_scores
    assert_equal 17, scores[@u1.username], "all-time reads the account balance"
    assert_equal 4, scores[@u2.username]
  end

  test "negative adjustment reduces all-time balance but not weekly earnings" do
    sign_in_private_viewer
    award_points(@u1, 10)
    award_points(@u1, -4)

    get forum_leaderboard_path(period: "week", metric: "points")
    assert_response :success
    assert_equal 10, points_scores[@u1.username], "weekly board sums positive transactions only"

    get forum_leaderboard_path(period: "all", metric: "points")
    assert_response :success
    assert_equal 6, points_scores[@u1.username], "all-time board reflects the deducted balance"
  end

  test "month points includes transactions older than a week but within a month" do
    sign_in_private_viewer
    award_points(@u1, 8, at: 2.weeks.ago)

    get forum_leaderboard_path(period: "month", metric: "points")
    assert_response :success
    assert_equal 8, points_scores[@u1.username]

    get forum_leaderboard_path(period: "week", metric: "points")
    assert_response :success
    assert_not_includes points_scores.keys, @u1.username
  end

  test "public viewers cannot request the private points leaderboard" do
    award_points(@u1, 99)

    get forum_leaderboard_path(metric: "points")

    assert_response :success
    props = inertia.props.deep_symbolize_keys
    assert_equal "posts", props.fetch(:metric)
    assert_not_includes props.fetch(:availableMetrics), "points"
    assert_equal 5, props.fetch(:entries).first.fetch(:score)
  end

  private

  def sign_in_private_viewer
    viewer = create_user
    grant_permission(viewer, Community::UserProfileVisibility::PRIVATE_ACTIVITY_PERMISSION)
    sign_in_as(viewer)
  end

  def award_points(user, amount, at: nil)
    result = Community::AwardPoints.call(user: user, amount: amount, reason: "admin_adjust")
    assert result.success?, "award_points failed: #{result.error}"
    Community::PointTransaction.where(id: result.value[:transaction].id).update_all(created_at: at) if at
  end

  def points_scores
    inertia.props.deep_symbolize_keys[:entries].to_h { |e| [ e[:username], e[:score] ] }
  end

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

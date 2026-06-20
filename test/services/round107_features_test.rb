# frozen_string_literal: true

require "test_helper"

class Round107NotificationLastYearFilterTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    Notification.create!(user: @user, notification_type: "forum.mention", title: "LastYearNotify", body: "b", created_at: Time.zone.local(2025, 8, 20, 12, 0, 0))
    Notification.create!(user: @user, notification_type: "forum.reaction", title: "AncientNotify", body: "b", created_at: 2.years.ago)
    sign_in_as(@user)
  end

  test "notifications index supports last year period filter" do
    travel_to Time.zone.local(2026, 6, 14, 12, 0, 0) do
      get forum_notifications_path(period: "last_year")
      assert_response :success
      assert_includes response.body, '"period":"last_year"'
      assert_includes response.body, "LastYearNotify"
      refute_includes response.body, "AncientNotify"
    end
  end
end

class Round107WarningPointsExpiryTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @mod = create_user
    grant_permission(@mod, "forum.users.warn")
    SiteSetting.set("forum.warning_points_expire_days", "90")
  end

  test "expired warnings do not count toward total" do
    Community::UserWarning.create!(
      user: @user,
      issuer: @mod,
      reason: "Old",
      points: 5,
      expires_at: 1.day.ago
    )
    Community::UserWarning.create!(
      user: @user,
      issuer: @mod,
      reason: "Active",
      points: 3,
      expires_at: 10.days.from_now
    )

    assert_equal 3, Community::UserWarning.total_points_for(@user)
  end

  test "create user warning sets expires_at from site setting" do
    result = Community::CreateUserWarning.call(actor: @mod, user: @user, reason: "Spam", points: 2)
    assert result.success?
    assert result.value.expires_at.present?
    assert result.value.expires_at > 89.days.from_now
  end
end

class Round107SectionPrefixesTest < ActiveSupport::TestCase
  test "normalizes string prefixes and resolves colors" do
    raw = [ "公告", { "name" => "求助", "color_hex" => "#ef4444" } ]
    names = Community::SectionPrefixes.names(raw)
    assert_equal %w[公告 求助], names
    assert_equal "#ef4444", Community::SectionPrefixes.color_for(raw, "求助")
  end

  test "parses admin form text with colors" do
    parsed = Community::SectionPrefixes.parse_form("公告\n求助|#22c55e")
    assert_equal "公告", parsed.first["name"]
    assert_equal "#22c55e", parsed.last["color_hex"]
  end
end

class Round107LoginRequiredSectionTest < ActionDispatch::IntegrationTest
  setup do
    category = Community::Category.find_or_create_by!(slug: "r107-private") { |c| c.name = "Private" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r107-members") do |s|
      s.name = "Members"
      s.position = 0
      s.login_required = true
    end
    @user = create_user
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Private topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    Community::Post.create!(topic: @topic, user: @user, body: "Hello", floor_number: 1, status: "published")
  end

  test "guest cannot view login required section" do
    get forum_section_path(@section)
    assert_redirected_to identity_sign_in_path
  end

  test "guest cannot view topic in login required section" do
    get forum_topic_path(@topic)
    assert_redirected_to identity_sign_in_path
  end

  test "logged in user can view login required section" do
    sign_in_as(@user)
    get forum_section_path(@section)
    assert_response :success
  end
end

class Round107UnreadFilterPresetUrlTest < ActiveSupport::TestCase
  test "builds shareable unread preset url" do
    url = Community::UnreadFilterPresetUrl.call(
      base_url: "http://example.com",
      filters: { sort: "hot", section: "general", tags: "bug", tag_match: "any" }
    )
    assert_includes url, "/forum/unread"
    assert_includes url, "sort=hot"
    assert_includes url, "section=general"
    assert_includes url, "tags=bug"
    assert_includes url, "tag_match=any"
  end
end

class Round107MailerUnsubscribeTest < ActionDispatch::IntegrationTest
  test "badge earned mail includes notification unsubscribe" do
    user = create_user
    badge = Community::Badge.first || Community::Badge.create!(name: "Test", slug: "test-#{SecureRandom.hex(3)}", icon: "⭐", description: "d")
    mail = Community::ForumMailer.badge_earned(user.id, badge.id)
    assert_includes mail.body.encoded, "forum/notifications/email/unsubscribe"
  end
end

class Round107SerializeTopicPrefixColorTest < ActionDispatch::IntegrationTest
  setup do
    category = Community::Category.find_or_create_by!(slug: "r107-prefix") { |c| c.name = "P" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r107-prefix-sec") do |s|
      s.name = "PrefixSec"
      s.position = 0
      s.prefixes = [ { "name" => "公告", "color_hex" => "#ef4444" } ]
    end
    @user = create_user
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Colored prefix topic",
      prefix: "公告",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    Community::Post.create!(topic: @topic, user: @user, body: "Body", floor_number: 1, status: "published")
    sign_in_as(@user)
  end

  test "topic list serialization includes prefix color" do
    get forum_section_path(@section)
    assert_response :success
    assert_includes response.body, '"prefix_color":"#ef4444"'
  end
end

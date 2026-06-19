# frozen_string_literal: true

require "test_helper"

class Round106GroupNotificationLastYearTest < ActiveSupport::TestCase
  test "groups notifications into last year bucket" do
    travel_to Time.zone.local(2026, 6, 14, 12, 0, 0) do
      last_year = Time.zone.local(2025, 8, 20, 12, 0, 0)
      groups = [ { key: "ly", latest_at_ts: last_year.to_i } ]
      sections = Community::GroupNotificationTimeline.call(groups)
      assert_equal 1, sections.size
      assert_equal "last_year", sections.first[:key]
      assert_equal "去年", sections.first[:label]
    end
  end
end

class Round106NotificationLastMonthFilterTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    Notification.create!(user: @user, notification_type: "forum.mention", title: "LastMonth", body: "b", created_at: Time.zone.now.beginning_of_month.prev_month + 5.days)
    Notification.create!(user: @user, notification_type: "forum.reaction", title: "AncientNotify", body: "b", created_at: 2.years.ago)
    sign_in_as(@user)
  end

  test "notifications index supports last month period filter" do
    get forum_notifications_path(period: "last_month")
    assert_response :success
    assert_includes response.body, "activePeriod"
    assert_includes response.body, '"period":"last_month"'
    assert_includes response.body, "LastMonth"
    refute_includes response.body, "AncientNotify"
  end
end

class Round106UnreadFilterPresetTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r106-unread") { |c| c.name = "U" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r106-unread-sec") { |s| s.name = "UnreadSec"; s.position = 0 }
    @tag = Community::Tag.create!(name: "R106Tag", slug: "r106-tag-#{SecureRandom.hex(3)}")
    sign_in_as(@user)
  end

  test "creates unread filter preset" do
    post forum_unread_filter_presets_path, params: {
      unread_filter_preset: {
        name: "热门分区",
        filters: { sort: "hot", section: @section.slug, tags: @tag.slug, tag_match: "any" }
      }
    }, as: :json

    assert_response :created
    preset = @user.forum_unread_filter_presets.find_by!(name: "热门分区")
    assert_equal @section.slug, preset.filters["section"]
  end

  test "unread page exposes saved filter presets" do
    Community::UnreadFilterPreset.create!(
      user: @user,
      name: "我的筛选",
      filters: { sort: "hot", section: @section.slug }
    )

    get forum_unread_path
    assert_response :success
    assert_includes response.body, "savedFilterPresets"
    assert_includes response.body, "saveFilterPresetUrl"
    assert_includes response.body, "我的筛选"
  end

  test "destroys unread filter preset" do
    preset = Community::UnreadFilterPreset.create!(
      user: @user,
      name: "删除测试",
      filters: { filter: "unanswered" }
    )

    delete forum_unread_filter_preset_path(preset), as: :json
    assert_response :no_content
    refute Community::UnreadFilterPreset.exists?(preset.id)
  end
end

class Round106TopicSolvedInviteUnsubscribeTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @actor = create_user
    @inviter = create_user
    category = Community::Category.find_or_create_by!(slug: "r106-mail") { |c| c.name = "M" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r106-mail-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @user,
      title: "Solved topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    @post = Community::Post.create!(topic: @topic, user: @actor, floor_number: 1, body: "Answer", status: "published")
  end

  test "topic solved email includes unsubscribe link" do
    email = Community::ForumMailer.topic_solved(@user.id, @topic.public_id, @post.id, @actor.id)
    body = email.html_part&.body&.decoded || email.body.decoded
    assert_includes body, "关闭此类邮件通知"
  end

  test "topic invite email includes unsubscribe link" do
    email = Community::ForumMailer.topic_invite(@user.id, @topic.public_id, @inviter.id)
    body = email.html_part&.body&.decoded || email.body.decoded
    assert_includes body, "关闭此类邮件通知"
  end
end

class Round106OrderExportUrlCopyTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    Commerce::Order.create!(
      public_id: "ord_r106_#{SecureRandom.hex(8)}",
      order_number: "R106#{SecureRandom.hex(3)}",
      user: @user,
      status: "paid",
      subtotal_cents: 12000,
      total_cents: 12000,
      currency: "CNY"
    )
    sign_in_as(@user)
  end

  test "orders index exposes export url for copy" do
    get store_orders_path(status: "paid", min_total: "100")
    assert_response :success
    assert_includes response.body, "exportUrl"
    assert_includes response.body, "export.csv"
    assert_includes response.body, "status=paid"
    assert_includes response.body, "min_total=100"
  end
end

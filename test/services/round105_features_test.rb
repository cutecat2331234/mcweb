# frozen_string_literal: true

require "test_helper"

class Round105GroupNotificationLastMonthTest < ActiveSupport::TestCase
  test "groups notifications into last month bucket" do
    travel_to Time.zone.local(2026, 6, 14, 12, 0, 0) do
      last_month = Time.zone.local(2026, 5, 20, 12, 0, 0)
      groups = [ { key: "lm", latest_at_ts: last_month.to_i } ]
      sections = Community::GroupNotificationTimeline.call(groups)
      assert_equal 1, sections.size
      assert_equal "last_month", sections.first[:key]
      assert_equal "上月", sections.first[:label]
    end
  end
end

class Round105NotificationThisMonthFilterTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    Notification.create!(user: @user, notification_type: "forum.mention", title: "ThisMonth", body: "b", created_at: Time.zone.now.beginning_of_month + 1.day)
    Notification.create!(user: @user, notification_type: "forum.reaction", title: "Old", body: "b", created_at: 2.months.ago)
    sign_in_as(@user)
  end

  test "notifications index supports this month period filter" do
    get forum_notifications_path(period: "this_month")
    assert_response :success
    assert_includes response.body, "activePeriod"
    assert_includes response.body, '"period":"this_month"'
    assert_includes response.body, "ThisMonth"
    refute_includes response.body, "Old"
  end
end

class Round105UnreadFilterBookmarkTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r105-unread") { |c| c.name = "U" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r105-unread-sec") { |s| s.name = "UnreadSec"; s.position = 0 }
    @tag = Community::Tag.create!(name: "R105Tag", slug: "r105-tag-#{SecureRandom.hex(3)}")
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Bookmark unread",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 1
    )
    @topic.tags << @tag
    Community::Post.create!(topic: @topic, user: @user, floor_number: 1, body: "Hi", status: "published")
    Community::Post.create!(topic: @topic, user: @user, floor_number: 2, body: "Reply", status: "published")
    Community::ReadState.find_or_create_by!(user: @user, topic: @topic) { |rs| rs.last_read_floor = 1 }
    sign_in_as(@user)
  end

  test "unread page exposes filter bookmark url" do
    get forum_unread_path(section: @section.slug, tags: @tag.slug, tag_match: "any", sort: "hot")
    assert_response :success
    assert_includes response.body, "filterBookmarkUrl"
    assert_includes response.body, @section.slug
    assert_includes response.body, @tag.slug
    assert_includes response.body, "tag_match=any"
    assert_includes response.body, "sort=hot"
  end
end

class Round105PostQuotedUnsubscribeTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @quoter = create_user
    category = Community::Category.find_or_create_by!(slug: "r105-quote") { |c| c.name = "Q" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r105-quote-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @user,
      title: "Quoted topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    @quoted_post = Community::Post.create!(topic: @topic, user: @user, floor_number: 1, body: "Original", status: "published")
    @post = Community::Post.create!(topic: @topic, user: @quoter, floor_number: 2, body: "Quote", status: "published", parent_post_id: @quoted_post.id)
  end

  test "post quoted email includes unsubscribe link" do
    email = Community::ForumMailer.post_quoted(@user.id, @post.id, @quoter.id, @quoted_post.id)
    body = email.html_part&.body&.decoded || email.body.decoded
    assert_includes body, "关闭此类邮件通知"
  end
end

class Round105OrderExportTotalPresetTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    Commerce::Order.create!(
      public_id: "ord_r105l_#{SecureRandom.hex(8)}",
      order_number: "LOW#{SecureRandom.hex(3)}",
      user: @user,
      status: "paid",
      subtotal_cents: 5000,
      total_cents: 5000,
      currency: "CNY"
    )
    Commerce::Order.create!(
      public_id: "ord_r105h_#{SecureRandom.hex(8)}",
      order_number: "HIGH#{SecureRandom.hex(3)}",
      user: @user,
      status: "paid",
      subtotal_cents: 80000,
      total_cents: 80000,
      currency: "CNY"
    )
    sign_in_as(@user)
  end

  test "export respects total preset filters" do
    get export_store_orders_path(format: :csv, min_total: "500")
    assert_response :success
    assert_includes response.body, "HIGH"
    refute_includes response.body, "LOW"
  end

  test "export url includes total preset params" do
    get store_orders_path(min_total: "500")
    assert_response :success
    assert_includes response.body, "export.csv"
    assert_includes response.body, "min_total=500"
  end
end

class Round105UnreadFilterBookmarkUrlTest < ActiveSupport::TestCase
  test "builds bookmark url only when filters present" do
    url = Community::UnreadFilterBookmarkUrl.call(
      base_url: "http://example.com",
      sort: "latest",
      filter: "",
      section: "",
      tags: [],
      tag_match: "all"
    )
    assert_nil url

    url = Community::UnreadFilterBookmarkUrl.call(
      base_url: "http://example.com",
      sort: "hot",
      filter: "",
      section: "general",
      tags: [ "ruby" ],
      tag_match: "any"
    )
    assert_includes url, "/forum/unread"
    assert_includes url, "section=general"
    assert_includes url, "tags=ruby"
    assert_includes url, "tag_match=any"
    assert_includes url, "sort=hot"
  end
end

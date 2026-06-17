# frozen_string_literal: true

require "test_helper"

class Round104GroupNotificationThisMonthTest < ActiveSupport::TestCase
  test "groups notifications into this month bucket" do
    travel_to Time.zone.local(2026, 6, 14, 12, 0, 0) do
      earlier_in_month = Time.zone.local(2026, 6, 1, 12, 0, 0)
      groups = [ { key: "m", latest_at_ts: earlier_in_month.to_i } ]
      sections = Community::GroupNotificationTimeline.call(groups)
      assert_equal 1, sections.size
      assert_equal "this_month", sections.first[:key]
      assert_equal "本月", sections.first[:label]
    end
  end
end

class Round104NotificationThisWeekFilterTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    Notification.create!(user: @user, notification_type: "forum.mention", title: "ThisWeek", body: "b", created_at: Time.zone.now.beginning_of_week + 1.day)
    Notification.create!(user: @user, notification_type: "forum.reaction", title: "Old", body: "b", created_at: 20.days.ago)
    sign_in_as(@user)
  end

  test "notifications index supports this week period filter" do
    get forum_notifications_path(period: "this_week")
    assert_response :success
    assert_includes response.body, "activePeriod"
    assert_includes response.body, '"period":"this_week"'
    assert_includes response.body, "ThisWeek"
    refute_includes response.body, "Old"
  end
end

class Round104UnreadTagOrFilterTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r104-unread") { |c| c.name = "U" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r104-unread-sec") { |s| s.name = "S"; s.position = 0 }
    @tag_a = Community::Tag.create!(name: "R104A", slug: "r104-a-#{SecureRandom.hex(3)}")
    @tag_b = Community::Tag.create!(name: "R104B", slug: "r104-b-#{SecureRandom.hex(3)}")
    @topic_a = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @user,
      title: "Tag A only",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 1
    )
    @topic_a.tags << @tag_a
    @topic_b = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @user,
      title: "Tag B only",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 1
    )
    @topic_b.tags << @tag_b
    [ @topic_a, @topic_b ].each do |topic|
      Community::Post.create!(topic: topic, user: @user, floor_number: 1, body: "Hi", status: "published")
      Community::Post.create!(topic: topic, user: @user, floor_number: 2, body: "Reply", status: "published")
      Community::ReadState.find_or_create_by!(user: @user, topic: topic) { |rs| rs.last_read_floor = 1 }
    end
    sign_in_as(@user)
  end

  test "unread page supports tag OR filter" do
    get forum_unread_path(tags: "#{@tag_a.slug},#{@tag_b.slug}", tag_match: "any")
    assert_response :success
    assert_includes response.body, "tagMatch"
    assert_includes response.body, "Tag A only"
    assert_includes response.body, "Tag B only"
  end

  test "unread page AND filter excludes single-tag topics" do
    get forum_unread_path(tags: "#{@tag_a.slug},#{@tag_b.slug}", tag_match: "all")
    assert_response :success
    refute_includes response.body, "Tag A only"
    refute_includes response.body, "Tag B only"
  end
end

class Round104OrderPresetStatusLinkageTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    Commerce::Order.create!(
      public_id: "ord_r104p_#{SecureRandom.hex(8)}",
      order_number: "PAID#{SecureRandom.hex(3)}",
      user: @user,
      status: "paid",
      subtotal_cents: 5000,
      total_cents: 5000,
      currency: "CNY"
    )
    Commerce::Order.create!(
      public_id: "ord_r104c_#{SecureRandom.hex(8)}",
      order_number: "CAN#{SecureRandom.hex(3)}",
      user: @user,
      status: "cancelled",
      subtotal_cents: 5000,
      total_cents: 5000,
      currency: "CNY"
    )
    sign_in_as(@user)
  end

  test "total presets preserve status filter in href" do
    get store_orders_path(status: "paid", max_total: "100")
    assert_response :success
    assert_includes response.body, "totalPresets"
    assert_includes response.body, "status=paid"
    assert_includes response.body, "PAID"
    refute_includes response.body, "CAN"
  end
end

class Round104TagTopicUnsubscribeTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @author = create_user
    category = Community::Category.find_or_create_by!(slug: "r104-tag") { |c| c.name = "T" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r104-tag-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @author,
      title: "Tag topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
  end

  test "tag topic email includes unsubscribe link" do
    email = Community::ForumMailer.tag_topic(@user.id, @topic.public_id, "Ruby")
    body = email.html_part&.body&.decoded || email.body.decoded
    assert_includes body, "关闭此类邮件通知"
  end
end

class Round104FollowedTopicUnsubscribeTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @author = create_user
    category = Community::Category.find_or_create_by!(slug: "r104-follow") { |c| c.name = "F" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r104-follow-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @author,
      title: "Followed topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
  end

  test "followed topic email includes unsubscribe link" do
    email = Community::ForumMailer.followed_topic(@user.id, @topic.public_id)
    body = email.html_part&.body&.decoded || email.body.decoded
    assert_includes body, "关闭此类邮件通知"
  end
end

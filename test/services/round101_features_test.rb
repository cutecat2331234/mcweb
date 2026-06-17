# frozen_string_literal: true

require "test_helper"

class Round101GroupNotificationsByReadStateTest < ActiveSupport::TestCase
  test "splits groups into unread and read sections" do
    groups = [
      { key: "a", read: false, title: "A" },
      { key: "b", read: true, title: "B" },
      { key: "c", read: false, title: "C" }
    ]
    sections = Community::GroupNotificationsByReadState.call(groups)
    assert_equal 2, sections.size
    assert_equal "未读", sections.first[:label]
    assert_equal 2, sections.first[:count]
    assert sections.first[:default_expanded]
    refute sections.last[:default_expanded]
  end
end

class Round101NotificationTypeUnsubscribeTokenTest < ActiveSupport::TestCase
  setup do
    @user = create_user
  end

  test "generates and verifies token" do
    token = Community::NotificationTypeUnsubscribeToken.generate(@user, notification_type: "forum.mention")
    user_id, type = Community::NotificationTypeUnsubscribeToken.verify(token)
    assert_equal @user.id, user_id
    assert_equal "forum.mention", type
  end
end

class Round101NotificationSectionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    Notification.create!(user: @user, notification_type: "forum.mention", title: "Unread", body: "b")
    Notification.create!(user: @user, notification_type: "forum.reaction", title: "Read", body: "b", read_at: Time.current)
    sign_in_as(@user)
  end

  test "notifications index includes grouped sections" do
    get forum_notifications_path
    assert_response :success
    assert_includes response.body, "notificationSections"
    assert_includes response.body, '"key":"unread"'
    assert_includes response.body, '"key":"read"'
  end
end

class Round101MentionUnsubscribeTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r101-cat") { |c| c.name = "C" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r101-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @user,
      title: "Mention topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    @post = Community::Post.create!(topic: @topic, user: @user, floor_number: 1, body: "Hi @user", status: "published")
    NotificationPreference.set!(@user, channel: "email", notification_type: "forum.mention", enabled: true)
  end

  test "mention email includes unsubscribe link" do
    email = Community::ForumMailer.mention(@user.id, @topic.public_id, @post.id)
    body = email.html_part&.body&.decoded || email.body.decoded
    assert_includes body, "关闭此类邮件通知"
  end

  test "unsubscribe disables mention email preference" do
    token = Community::NotificationTypeUnsubscribeToken.generate(@user, notification_type: "forum.mention")
    get forum_unsubscribe_notification_type_path(token: token)
    assert_redirected_to forum_preferences_path
    refute NotificationPreference.enabled?(@user, channel: "email", notification_type: "forum.mention")
  end
end

class Round101UnreadSectionFilterTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r101-unread") { |c| c.name = "U" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r101-unread-sec") { |s| s.name = "UnreadSec"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Unread section",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 1
    )
    Community::Post.create!(topic: @topic, user: @user, floor_number: 1, body: "Hi", status: "published")
    Community::Post.create!(topic: @topic, user: @user, floor_number: 2, body: "Reply", status: "published")
    Community::ReadState.find_or_create_by!(user: @user, topic: @topic) { |rs| rs.last_read_floor = 1 }
    sign_in_as(@user)
  end

  test "unread page supports section filter" do
    get forum_unread_path(section: @section.slug)
    assert_response :success
    assert_includes response.body, "sectionOptions"
    assert_includes response.body, @section.slug
    assert_includes response.body, "UnreadSec"
  end
end

class Round101PollTwitterMetaTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r101-poll") { |c| c.name = "P" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r101-poll-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @user,
      title: "Poll twitter",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    Community::Post.create!(topic: @topic, user: @user, floor_number: 1, body: "Hi", status: "published")
    Community::Poll.create!(topic: @topic, question: "Best?", options: %w[A B])
    sign_in_as(@user)
  end

  test "poll topic includes twitter meta" do
    get forum_topic_path(@topic)
    assert_response :success
    assert_includes response.body, "twitter_card"
    assert_includes response.body, "summary"
  end
end

class Round101OrderDateFiltersTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    Commerce::Order.create!(
      public_id: "ord_r101_#{SecureRandom.hex(8)}",
      order_number: "OLD#{SecureRandom.hex(3)}",
      user: @user,
      status: "paid",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY",
      created_at: 10.days.ago
    )
    Commerce::Order.create!(
      public_id: "ord_r101n_#{SecureRandom.hex(8)}",
      order_number: "NEW#{SecureRandom.hex(3)}",
      user: @user,
      status: "paid",
      subtotal_cents: 2000,
      total_cents: 2000,
      currency: "CNY",
      created_at: 1.day.ago
    )
    sign_in_as(@user)
  end

  test "orders index supports date filters and chips" do
    get store_orders_path(created_after: 3.days.ago.to_date.to_s)
    assert_response :success
    assert_includes response.body, "createdAfter"
    assert_includes response.body, "activeFilters"
    assert_includes response.body, "NEW"
    refute_includes response.body, "OLD"
  end

  test "export respects date filter" do
    get export_store_orders_path(format: :csv, created_after: 3.days.ago.to_date.to_s)
    assert_response :success
    assert_includes response.body, "NEW"
    refute_includes response.body, "OLD"
  end
end

# frozen_string_literal: true

require "test_helper"

class Round99NotificationTypeLabelsTest < ActiveSupport::TestCase
  test "labels forum and commerce notification types" do
    assert_equal "主题回复", Community::NotificationTypeLabels.label_for("forum.topic_reply")
    assert_equal "支付确认", Community::NotificationTypeLabels.label_for("commerce.payment_confirmed")
  end
end

class Round99NotificationActiveFiltersTest < ActiveSupport::TestCase
  test "builds notification filter chips" do
    chips = Community::NotificationActiveFilters.call(
      category: "forum",
      read: "unread",
      type: "forum.mention"
    )
    assert_equal 3, chips.size
    assert chips.any? { |c| c[:param] == "category" && c[:label] == "论坛" }
    assert chips.any? { |c| c[:param] == "read" }
    assert chips.any? { |c| c[:param] == "type" && c[:label] == "@提及" }
  end
end

class Round99TopicListActiveFiltersTest < ActiveSupport::TestCase
  test "builds topic list filter chips" do
    chips = Community::TopicListActiveFilters.call(filter: "unsolved")
    assert_equal 1, chips.size
    assert_equal "未解决", chips.first[:label]
  end

  test "builds prefix filter chip" do
    chips = Community::TopicListActiveFilters.call(filter: "prefix:公告", prefixes: %w[公告])
    assert_equal "前缀：公告", chips.first[:label]
  end
end

class Round99NotificationsTypeTabsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    Notification.create!(
      user: @user,
      notification_type: "forum.mention",
      title: "Mention",
      body: "body"
    )
    Notification.create!(
      user: @user,
      notification_type: "forum.topic_reply",
      title: "Reply",
      body: "body"
    )
    sign_in_as(@user)
  end

  test "notifications index includes type tabs and active filters" do
    get forum_notifications_path(read: "unread", type: "forum.mention")
    assert_response :success
    assert_includes response.body, "typeTabs"
    assert_includes response.body, "activeFilters"
    assert_includes response.body, "forum.mention"
  end
end

class Round99LatestActiveFiltersTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in_as(@user)
  end

  test "latest page passes active filters" do
    get forum_latest_path(filter: "unsolved")
    assert_response :success
    assert_includes response.body, "activeFilters"
    assert_includes response.body, "未解决"
  end
end

class Round99DigestUnreadLinkTest < ActionMailer::TestCase
  setup do
    @user = create_user
    @notification = Notification.create!(
      user: @user,
      notification_type: "forum.reaction",
      title: "Reaction",
      body: "Someone reacted",
      metadata: { path: "/forum/topics/topic1" }
    )
  end

  test "digest email includes unread notifications link" do
    email = Community::ForumMailer.digest(@user.id, [ @notification.id ])
    assert_includes email.html_part.body.decoded, "read=unread"
    assert_includes email.html_part.body.decoded, "查看全部未读通知"
  end
end

class Round99PollShareUrlTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r99-poll") { |c| c.name = "P" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r99-poll-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @user,
      title: "Poll share",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    Community::Post.create!(topic: @topic, user: @user, floor_number: 1, body: "Hi", status: "published")
    Community::Poll.create!(topic: @topic, question: "Q?", options: %w[A B])
    sign_in_as(@user)
  end

  test "topic poll includes share_url" do
    get forum_topic_path(@topic)
    assert_response :success
    assert_includes response.body, "share_url"
    assert_includes response.body, "#poll"
  end
end

class Round99StoreOrdersStatusSyncTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    Commerce::Order.create!(
      public_id: "ord_r99_#{SecureRandom.hex(8)}",
      order_number: "PAID#{SecureRandom.hex(4)}",
      user: @user,
      status: "paid",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY"
    )
    sign_in_as(@user)
  end

  test "orders index includes status tabs for sync" do
    get store_orders_path(status: "paid")
    assert_response :success
    assert_includes response.body, "statusTabs"
    assert_includes response.body, '"active":true'
  end
end

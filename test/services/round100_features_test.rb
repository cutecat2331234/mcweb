# frozen_string_literal: true

require "test_helper"

class Round100NotificationQuickFiltersTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    Notification.create!(user: @user, notification_type: "forum.mention", title: "M", body: "b")
    Notification.create!(user: @user, notification_type: "forum.topic_reply", title: "R", body: "b")
  end

  test "builds quick filters with counts" do
    filters = Community::NotificationQuickFilters.call(user: @user, category: nil, read: nil, active_type: nil)
    assert filters.any? { |f| f[:type] == "forum.mention" }
    assert filters.any? { |f| f[:type] == "forum.topic_reply" }
    assert filters.all? { |f| f[:count].positive? }
  end
end

class Round100TopicListSortActiveFiltersTest < ActiveSupport::TestCase
  test "builds sort chip when not default" do
    chips = Community::TopicListSortActiveFilters.call(sort: "hot", default: "activity")
    assert_equal 1, chips.size
    assert_includes chips.first[:label], "热门"
  end

  test "omits chip for default sort" do
    assert_empty Community::TopicListSortActiveFilters.call(sort: "latest", default: "latest")
  end
end

class Round100NotificationTypeTabsUnreadTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    Notification.create!(user: @user, notification_type: "forum.mention", title: "M", body: "b")
    Notification.create!(user: @user, notification_type: "forum.mention", title: "M2", body: "b", read_at: Time.current)
    Notification.create!(user: @user, notification_type: "forum.reaction", title: "R", body: "b")
    sign_in_as(@user)
  end

  test "notifications include quick filters and unread counts on type tabs" do
    get forum_notifications_path
    assert_response :success
    assert_includes response.body, "quickFilters"
    assert_includes response.body, "unread_count"
    assert_includes response.body, "forum.mention"
  end
end

class Round100UnreadFiltersTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r100-cat") { |c| c.name = "R100" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r100-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @user,
      title: "Unread unsolved",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 1,
      solved_post_id: nil
    )
    Community::Post.create!(topic: @topic, user: @user, floor_number: 1, body: "Hi", status: "published")
    Community::Post.create!(topic: @topic, user: @user, floor_number: 2, body: "Reply", status: "published")
    Community::ReadState.find_or_create_by!(user: @user, topic: @topic) do |rs|
      rs.last_read_floor = 1
    end
    sign_in_as(@user)
  end

  test "unread page supports filter and active filters" do
    get forum_unread_path(filter: "unsolved", sort: "hot")
    assert_response :success
    assert_includes response.body, "filterOptions"
    assert_includes response.body, "activeFilters"
    assert_includes response.body, "未解决"
    assert_includes response.body, "热门"
  end
end

class Round100PollOgMetaTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r100-poll") { |c| c.name = "P" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r100-poll-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @user,
      title: "Poll OG",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    Community::Post.create!(topic: @topic, user: @user, floor_number: 1, body: "Hi", status: "published")
    Community::Poll.create!(topic: @topic, question: "Favorite color?", options: %w[Red Blue])
    sign_in_as(@user)
  end

  test "poll topic meta includes poll question and hash url" do
    get forum_topic_path(@topic)
    assert_response :success
    assert_includes response.body, "poll_question"
    assert_includes response.body, "#poll"
    assert_includes response.body, "Favorite color?"
  end
end

class Round100StoreOrdersTabSyncTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    Commerce::Order.create!(
      public_id: "ord_r100_#{SecureRandom.hex(8)}",
      order_number: "FINDME#{SecureRandom.hex(3)}",
      user: @user,
      status: "paid",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY"
    )
    sign_in_as(@user)
  end

  test "order status tabs include status field for client sync" do
    get store_orders_path(q: "FINDME", status: "paid")
    assert_response :success
    assert_includes response.body, '"status":"paid"'
    assert_includes response.body, "FINDME"
  end
end

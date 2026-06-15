# frozen_string_literal: true

require "test_helper"

class Round102GroupNotificationTimelineTest < ActiveSupport::TestCase
  test "groups notifications into today yesterday and earlier buckets" do
    now = Time.zone.now
    groups = [
      { key: "a", latest_at_ts: now.to_i },
      { key: "b", latest_at_ts: (now - 1.day).to_i },
      { key: "c", latest_at_ts: (now - 40.days).to_i }
    ]
    sections = Community::GroupNotificationTimeline.call(groups)
    assert_equal 3, sections.size
    assert_equal "today", sections[0][:key]
    assert_equal "yesterday", sections[1][:key]
    assert_equal "earlier", sections[2][:key]
    assert sections[0][:default_expanded]
    refute sections[2][:default_expanded]
  end
end

class Round102NotificationTimelineSectionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    Notification.create!(user: @user, notification_type: "forum.mention", title: "Today", body: "b", created_at: Time.zone.now)
    Notification.create!(user: @user, notification_type: "forum.reaction", title: "Earlier", body: "b", created_at: 40.days.ago)
    sign_in_as(@user)
  end

  test "notifications index includes timeline sections" do
    get forum_notifications_path
    assert_response :success
    assert_includes response.body, "timeline_sections"
    assert_includes response.body, '"key":"today"'
    assert_includes response.body, '"key":"earlier"'
  end
end

class Round102UnreadTagFilterTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r102-unread") { |c| c.name = "U" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r102-unread-sec") { |s| s.name = "S"; s.position = 0 }
    @tag = Community::Tag.create!(name: "R102Tag", slug: "r102-tag-#{SecureRandom.hex(3)}")
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @user,
      title: "Tagged unread",
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

  test "unread page supports tag filter" do
    get forum_unread_path(tag: @tag.slug)
    assert_response :success
    assert_includes response.body, "tagOptions"
    assert_includes response.body, @tag.slug
    assert_includes response.body, "R102Tag"
    assert_includes response.body, "Tagged unread"
  end
end

class Round102PollOgMetaTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r102-poll") { |c| c.name = "P" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r102-poll-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @user,
      title: "Poll og",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    Community::Post.create!(topic: @topic, user: @user, floor_number: 1, body: "Hi", status: "published")
    Community::Poll.create!(topic: @topic, question: "Best?", options: %w[A B])
    sign_in_as(@user)
  end

  test "poll topic includes og locale and site name" do
    get forum_topic_path(@topic)
    assert_response :success
    assert_includes response.body, "og_locale"
    assert_includes response.body, "zh_CN"
    assert_includes response.body, "og_site_name"
    assert_includes response.body, "Mcweb"
  end
end

class Round102OrderTotalFiltersTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    Commerce::Order.create!(
      public_id: "ord_r102l_#{SecureRandom.hex(8)}",
      order_number: "LOW#{SecureRandom.hex(3)}",
      user: @user,
      status: "paid",
      subtotal_cents: 5000,
      total_cents: 5000,
      currency: "CNY"
    )
    Commerce::Order.create!(
      public_id: "ord_r102h_#{SecureRandom.hex(8)}",
      order_number: "HIGH#{SecureRandom.hex(3)}",
      user: @user,
      status: "paid",
      subtotal_cents: 20000,
      total_cents: 20000,
      currency: "CNY"
    )
    sign_in_as(@user)
  end

  test "orders index supports total range filters" do
    get store_orders_path(min_total: "150")
    assert_response :success
    assert_includes response.body, "minTotal"
    assert_includes response.body, "activeFilters"
    assert_includes response.body, "HIGH"
    refute_includes response.body, "LOW"
  end

  test "export respects total filters" do
    get export_store_orders_path(format: :csv, min_total: "150")
    assert_response :success
    assert_includes response.body, "HIGH"
    refute_includes response.body, "LOW"
  end
end

class Round102NotificationEmailUnsubscribeTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @author = create_user
    category = Community::Category.find_or_create_by!(slug: "r102-mail") { |c| c.name = "M" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r102-mail-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @author,
      title: "Mail topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    @post = Community::Post.create!(topic: @topic, user: @author, floor_number: 1, body: "Hi", status: "published")
  end

  test "topic reply email includes unsubscribe link" do
    email = Community::ForumMailer.topic_reply(@user.id, @topic.public_id, @post.id)
    body = email.html_part&.body&.decoded || email.body.decoded
    assert_includes body, "关闭此类邮件通知"
  end

  test "followed reply email includes unsubscribe link" do
    email = Community::ForumMailer.followed_reply(@user.id, @topic.public_id, @post.id)
    body = email.html_part&.body&.decoded || email.body.decoded
    assert_includes body, "关闭此类邮件通知"
  end

  test "post reaction email includes unsubscribe link" do
    email = Community::ForumMailer.post_reaction(@user.id, @post.id, @author.id, "👍")
    body = email.html_part&.body&.decoded || email.body.decoded
    assert_includes body, "关闭此类邮件通知"
  end
end

class Round102DigestTypeUnsubscribeTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @notification = Notification.create!(
      user: @user,
      notification_type: "forum.topic_reply",
      title: "Reply",
      body: "New reply"
    )
  end

  test "digest email includes per-type unsubscribe links" do
    email = Community::ForumMailer.digest(@user.id, [ @notification.id ])
    body = email.html_part.body.decoded
    assert_includes body, "关闭此类邮件"
    assert_includes body, "notifications/email/unsubscribe"
  end
end

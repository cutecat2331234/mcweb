# frozen_string_literal: true

require "test_helper"

class Round103GroupNotificationThisWeekTest < ActiveSupport::TestCase
  test "groups notifications into this week bucket" do
    travel_to Time.zone.local(2026, 6, 14, 12, 0, 0) do
      wednesday = Time.zone.local(2026, 6, 11, 12, 0, 0)
      groups = [ { key: "w", latest_at_ts: wednesday.to_i } ]
      sections = Community::GroupNotificationTimeline.call(groups)
      assert_equal 1, sections.size
      assert_equal "this_week", sections.first[:key]
      assert_equal "本周", sections.first[:label]
    end
  end
end

class Round103NotificationPeriodFilterTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    Notification.create!(user: @user, notification_type: "forum.mention", title: "Today", body: "b", created_at: Time.zone.now)
    Notification.create!(user: @user, notification_type: "forum.reaction", title: "Old", body: "b", created_at: 3.days.ago)
    sign_in_as(@user)
  end

  test "notifications index supports today period filter" do
    get forum_notifications_path(period: "today")
    assert_response :success
    assert_includes response.body, "activePeriod"
    assert_includes response.body, "periodFilters"
    assert_includes response.body, "Today"
    refute_includes response.body, "Old"
  end
end

class Round103UnreadMultiTagFilterTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r103-unread") { |c| c.name = "U" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r103-unread-sec") { |s| s.name = "S"; s.position = 0 }
    @tag_a = Community::Tag.create!(name: "R103A", slug: "r103-a-#{SecureRandom.hex(3)}")
    @tag_b = Community::Tag.create!(name: "R103B", slug: "r103-b-#{SecureRandom.hex(3)}")
    @topic_both = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @user,
      title: "Both tags",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 1
    )
    @topic_both.tags << @tag_a << @tag_b
    @topic_one = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @user,
      title: "One tag only",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 1
    )
    @topic_one.tags << @tag_a
    [ @topic_both, @topic_one ].each do |topic|
      Community::Post.create!(topic: topic, user: @user, floor_number: 1, body: "Hi", status: "published")
      Community::Post.create!(topic: topic, user: @user, floor_number: 2, body: "Reply", status: "published")
      Community::ReadState.find_or_create_by!(user: @user, topic: topic) { |rs| rs.last_read_floor = 1 }
    end
    sign_in_as(@user)
  end

  test "unread page supports multi-tag AND filter" do
    get forum_unread_path(tags: "#{@tag_a.slug},#{@tag_b.slug}")
    assert_response :success
    assert_includes response.body, "Both tags"
    refute_includes response.body, "One tag only"
    assert_includes response.body, @tag_a.slug
    assert_includes response.body, @tag_b.slug
  end
end

class Round103OrderTotalPresetsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    Commerce::Order.create!(
      public_id: "ord_r103l_#{SecureRandom.hex(8)}",
      order_number: "LOW#{SecureRandom.hex(3)}",
      user: @user,
      status: "paid",
      subtotal_cents: 5000,
      total_cents: 5000,
      currency: "CNY"
    )
    Commerce::Order.create!(
      public_id: "ord_r103h_#{SecureRandom.hex(8)}",
      order_number: "HIGH#{SecureRandom.hex(3)}",
      user: @user,
      status: "paid",
      subtotal_cents: 60000,
      total_cents: 60000,
      currency: "CNY"
    )
    sign_in_as(@user)
  end

  test "orders index includes total presets" do
    get store_orders_path(max_total: "100")
    assert_response :success
    assert_includes response.body, "totalPresets"
    assert_includes response.body, "under_100"
    assert_includes response.body, "LOW"
    refute_includes response.body, "HIGH"
  end
end

class Round103PrivateMessageUnsubscribeTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @sender = create_user
    @conversation = Community::Conversation.create!(title: "DM")
    Community::ConversationParticipant.create!(conversation: @conversation, user: @user)
    Community::ConversationParticipant.create!(conversation: @conversation, user: @sender)
    @message = Community::Message.create!(conversation: @conversation, user: @sender, body: "Hello")
  end

  test "private message email includes unsubscribe link" do
    email = Community::ForumMailer.private_message(@user.id, @conversation.id, @message.id)
    body = email.html_part&.body&.decoded || email.body.decoded
    assert_includes body, "关闭此类邮件通知"
  end
end

class Round103SectionTopicUnsubscribeTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @author = create_user
    category = Community::Category.find_or_create_by!(slug: "r103-sec") { |c| c.name = "S" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r103-sec-sec") { |s| s.name = "Sec"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @author,
      title: "Section topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
  end

  test "section topic email includes unsubscribe link" do
    email = Community::ForumMailer.section_topic(@user.id, @topic.public_id)
    body = email.html_part&.body&.decoded || email.body.decoded
    assert_includes body, "关闭此类邮件通知"
  end
end

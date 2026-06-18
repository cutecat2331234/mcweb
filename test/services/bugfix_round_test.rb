# frozen_string_literal: true

require "test_helper"

class PostCounterTest < ActiveSupport::TestCase
  setup do
    @author = create_user
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    category = Community::Category.find_or_create_by!(slug: "counter-cat") { |c| c.name = "Counter" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "counter-sec") do |s|
      s.name = "Counter Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @author,
      section: @section,
      title: "Counter topic",
      body: "First post",
      ip_address: "127.0.0.1"
    ).value
  end

  test "regular reply increases replies_count" do
    Community::CreatePost.call(
      user: create_user,
      topic: @topic,
      body: "Visible reply",
      ip_address: "127.0.0.1",
      skip_interval_check: true
    )
    assert_equal 1, @topic.reload.replies_count
  end

  test "whisper does not increase replies_count" do
    Community::CreatePost.call(
      user: @mod,
      topic: @topic,
      body: "Secret whisper",
      whisper: true,
      ip_address: "127.0.0.1",
      skip_interval_check: true
    )
    assert_equal 0, @topic.reload.replies_count
  end

  test "small_action does not increase replies_count" do
    Community::CreateSmallActionPost.call(
      topic: @topic,
      actor: @mod,
      body: "关闭了投票"
    )
    assert_equal 0, @topic.reload.replies_count
  end
end

class UnreadFilterRedirectTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in_as(@user)
  end

  test "mark selected read preserves unread filters" do
    category = Community::Category.find_or_create_by!(slug: "unread-redir-cat") { |c| c.name = "UR" }
    section = Community::Section.find_or_create_by!(category: category, slug: "unread-redir-sec") do |s|
      s.name = "UR Sec"
      s.position = 0
    end
    topic = Community::CreateTopic.call(
      user: create_user,
      section: section,
      title: "Unread topic #{SecureRandom.hex(4)}",
      body: "Body",
      ip_address: "127.0.0.1"
    ).value
    Community::ReadState.mark_read!(@user, topic, floor: 0)
    Community::CreatePost.call(
      user: create_user,
      topic: topic,
      body: "Reply",
      ip_address: "127.0.0.1",
      skip_interval_check: true
    )

    patch forum_unread_mark_selected_read_path(sort: "hot", filter: "unsolved"),
          params: { topic_ids: [ topic.public_id ] }

    assert_redirected_to forum_unread_path(sort: "hot", filter: "unsolved")
  end

  test "invalid section slug returns empty unread list" do
    category = Community::Category.find_or_create_by!(slug: "unread-empty-cat") { |c| c.name = "UE" }
    section = Community::Section.find_or_create_by!(category: category, slug: "unread-empty-sec") do |s|
      s.name = "UE Sec"
      s.position = 0
    end
    title = "Unread only topic #{SecureRandom.hex(4)}"
    topic = Community::CreateTopic.call(
      user: create_user,
      section: section,
      title: title,
      body: "Body",
      ip_address: "127.0.0.1"
    ).value
    Community::ReadState.mark_read!(@user, topic, floor: 0)
    Community::CreatePost.call(
      user: create_user,
      topic: topic,
      body: "New reply",
      ip_address: "127.0.0.1",
      skip_interval_check: true
    )

    get forum_unread_path(section: section.slug)
    assert_response :success
    assert_includes @response.body, title

    get forum_unread_path(section: "missing-section-#{SecureRandom.hex(4)}")
    assert_response :success
    assert_not_includes @response.body, title
  end
end

class SectionMarkReadRedirectTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in_as(@user)
    category = Community::Category.find_or_create_by!(slug: "sec-redir-cat") { |c| c.name = "SR" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "sec-redir-sec") do |s|
      s.name = "SR Sec"
      s.position = 0
    end
  end

  test "mark all read preserves section sort and filter" do
    patch mark_all_read_forum_section_path(@section, sort: "hot", filter: "unsolved")

    assert_redirected_to forum_section_path(@section, sort: "hot", filter: "unsolved")
  end
end

class ConversationUnreadCountTest < ActiveSupport::TestCase
  setup do
    @alice = create_user
    enable_forum_pm!(@alice)
    @bob = create_user
    enable_forum_pm!(@bob)
    result = Community::CreateConversation.call(
      sender: @alice,
      recipient_username: @bob.username,
      body: "Hello"
    )
    @conversation = result.value[:conversation]
  end

  test "total_unread_count_for aggregates unread messages" do
    Community::SendMessage.call(user: @bob, conversation: @conversation, body: "Reply 1")
    Community::SendMessage.call(user: @bob, conversation: @conversation, body: "Reply 2")

    assert_equal 2, Community::Conversation.total_unread_count_for(@alice)
    assert_equal 0, Community::Conversation.total_unread_count_for(@bob)
  end

  test "total_unread_count_for excludes muted conversations" do
    Community::SendMessage.call(user: @bob, conversation: @conversation, body: "Reply")
    participant = @conversation.participants.find_by!(user: @alice)
    participant.update!(muted_at: Time.current)

    assert_equal 0, Community::Conversation.total_unread_count_for(@alice)
  end

  test "total_unread_count_for excludes archived conversations" do
    Community::SendMessage.call(user: @bob, conversation: @conversation, body: "Reply")
    participant = @conversation.participants.find_by!(user: @alice)
    participant.update!(archived_at: Time.current)

    assert_equal 0, Community::Conversation.total_unread_count_for(@alice)
    assert_equal 1, @conversation.unread_count_for(@alice)
  end
end

class HidePostCounterTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    @author = create_user
    category = Community::Category.find_or_create_by!(slug: "hide-cat") { |c| c.name = "Hide" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "hide-sec") do |s|
      s.name = "Hide Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @author,
      section: @section,
      title: "Hide counter topic",
      body: "OP",
      ip_address: "127.0.0.1"
    ).value
    @reply = Community::CreatePost.call(
      user: create_user,
      topic: @topic,
      body: "Visible reply",
      ip_address: "127.0.0.1",
      skip_interval_check: true
    ).value
  end

  test "hiding a reply decrements replies_count" do
    assert_equal 1, @topic.reload.replies_count

    result = Community::ModeratePost.call(user: @mod, post: @reply, action: "hide")
    assert result.success?
    assert_equal 0, @topic.reload.replies_count
  end
end

class UnreadMarkAllScopedTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in_as(@user)
    @cat = Community::Category.find_or_create_by!(slug: "scoped-cat") { |c| c.name = "SC" }
    @section_a = Community::Section.find_or_create_by!(category: @cat, slug: "scoped-a") { |s| s.name = "A"; s.position = 0 }
    @section_b = Community::Section.find_or_create_by!(category: @cat, slug: "scoped-b") { |s| s.name = "B"; s.position = 1 }
  end

  def create_unread_topic(section:, title:)
    topic = Community::CreateTopic.call(
      user: create_user,
      section: section,
      title: title,
      body: "Body",
      ip_address: "127.0.0.1"
    ).value
    Community::ReadState.mark_read!(@user, topic, floor: 0)
    Community::CreatePost.call(
      user: create_user,
      topic: topic,
      body: "Reply",
      ip_address: "127.0.0.1",
      skip_interval_check: true
    )
    topic
  end

  test "mark all read with section filter only clears that section" do
    topic_a = create_unread_topic(section: @section_a, title: "Topic A #{SecureRandom.hex(3)}")
    topic_b = create_unread_topic(section: @section_b, title: "Topic B #{SecureRandom.hex(3)}")

    patch forum_unread_mark_all_read_path(section: @section_a.slug)

    assert_redirected_to forum_unread_path(section: @section_a.slug)
    assert_not Community::ReadState.with_unread_for(@user).where(forum_topic_id: topic_a.id).exists?
    assert Community::ReadState.with_unread_for(@user).where(forum_topic_id: topic_b.id).exists?
  end
end

class NotificationMarkReadRedirectTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in_as(@user)
    @notification = Notification.create!(
      user: @user,
      notification_type: "forum.mention",
      title: "Test",
      body: "Body",
      metadata: {}
    )
  end

  test "mark read preserves notification filters" do
    patch mark_read_forum_notification_path(@notification, category: "forum", read: "unread")

    assert_redirected_to forum_notifications_path(category: "forum", read: "unread")
  end

  test "mark all read preserves notification filters" do
    Notification.create!(
      user: @user,
      notification_type: "forum.mention",
      title: "Unread",
      body: "Body",
      metadata: {}
    )

    patch mark_all_read_forum_notifications_path(category: "forum", read: "unread")

    assert_redirected_to forum_notifications_path(category: "forum", read: "unread")
  end
end

class MarkTopicsReadCountableTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    category = Community::Category.find_or_create_by!(slug: "mtr-cat") { |c| c.name = "MTR" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "mtr-sec") do |s|
      s.name = "MTR Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: create_user,
      section: @section,
      title: "Mark topics read",
      body: "OP",
      ip_address: "127.0.0.1"
    ).value
    Community::ReadState.mark_read!(@user, @topic, floor: 1)
    Community::CreatePost.call(
      user: create_user,
      topic: @topic,
      body: "Unread reply",
      ip_address: "127.0.0.1",
      skip_interval_check: true
    )
    Community::CreatePost.call(
      user: @mod,
      topic: @topic,
      body: "Trailing whisper",
      whisper: true,
      ip_address: "127.0.0.1",
      skip_interval_check: true
    )
  end

  test "mark topics read ignores trailing whisper floor" do
    result = Community::MarkTopicsRead.call(user: @user, topic_public_ids: [ @topic.public_id ])
    assert result.success?

    state = Community::ReadState.find_by!(user: @user, topic: @topic)
    assert_equal 2, state.last_read_floor
    assert_not Community::ReadState.with_unread_for(@user).where(forum_topic_id: @topic.id).exists?
  end
end

class ReadStateEnsureTrackingTest < ActiveSupport::TestCase
  setup do
    @author = create_user
    @watcher = create_user
    category = Community::Category.find_or_create_by!(slug: "track-cat") { |c| c.name = "Track" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "track-sec") do |s|
      s.name = "Track Sec"
      s.position = 0
    end
    Community::Subscription.subscribe!(@watcher, @section, level: "watching")
  end

  test "section topic notification creates read state for watcher who never visited" do
    topic = Community::CreateTopic.call(
      user: @author,
      section: @section,
      title: "Tracked topic",
      body: "OP",
      ip_address: "127.0.0.1"
    ).value

    assert Notification.exists?(user: @watcher, notification_type: "forum.section_topic")

    state = Community::ReadState.find_by(user: @watcher, topic: topic)
    assert state, "expected read state for notified watcher"
    assert_equal 0, state.last_read_floor
    assert state.unread_count.positive?
  end

  test "ensure_tracking creates read state without visiting topic" do
    topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @author,
      title: "Manual topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    Community::Post.create!(
      topic: topic,
      user: @author,
      floor_number: 1,
      body: "OP",
      status: "published",
      post_type: "regular"
    )

    assert_not Community::ReadState.exists?(user: @watcher, topic: topic)

    Community::ReadState.ensure_tracking!(@watcher, topic)

    state = Community::ReadState.find_by!(user: @watcher, topic: topic)
    assert_equal 0, state.last_read_floor
    assert state.unread_count.positive?
  end
end

class MarkTopicUnreadCountableTest < ActiveSupport::TestCase
  setup do
    @author = create_user
    @reader = create_user
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    category = Community::Category.find_or_create_by!(slug: "munread-cat") { |c| c.name = "MU" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "munread-sec") do |s|
      s.name = "MU Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @author,
      section: @section,
      title: "Mark unread",
      body: "OP",
      ip_address: "127.0.0.1"
    ).value
    Community::ReadState.mark_read!(@reader, @topic, floor: 1)
    @reply = Community::CreatePost.call(
      user: create_user,
      topic: @topic,
      body: "Regular reply",
      ip_address: "127.0.0.1",
      skip_interval_check: true
    ).value
    Community::CreatePost.call(
      user: @mod,
      topic: @topic,
      body: "Staff whisper",
      whisper: true,
      ip_address: "127.0.0.1",
      skip_interval_check: true
    )
  end

  test "mark unread ignores trailing whisper when computing read floor" do
    result = Community::MarkTopicUnread.call(user: @reader, topic: @topic)
    assert result.success?

    state = Community::ReadState.find_by!(user: @reader, topic: @topic)
    assert state.unread_count.positive?
  end
end

class SmallActionActivityTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "sa-cat") { |c| c.name = "SA" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "sa-sec") do |s|
      s.name = "SA Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Small action topic",
      body: "OP",
      ip_address: "127.0.0.1"
    ).value
    @before = @topic.last_posted_at
  end

  test "small action updates topic last_posted_at" do
    Community::CreateSmallActionPost.call(topic: @topic, actor: @mod, body: "锁定了主题")
    @topic.reload
    assert_equal @mod.id, @topic.last_post_user_id
    assert_operator @topic.last_posted_at, :>=, @before
  end
end

class SectionMuteRedirectTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in_as(@user)
    category = Community::Category.find_or_create_by!(slug: "mute-cat") { |c| c.name = "M" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "mute-sec") do |s|
      s.name = "Mute Sec"
      s.position = 0
    end
  end

  test "toggle mute preserves section sort and filter" do
    post mute_forum_section_path(@section, sort: "hot", filter: "unsolved")

    assert_redirected_to forum_section_path(@section, sort: "hot", filter: "unsolved")
  end
end

class ArchivedConversationAccessTest < ActionDispatch::IntegrationTest
  setup do
    @alice = create_user
    enable_forum_pm!(@alice)
    @bob = create_user
    enable_forum_pm!(@bob)
    result = Community::CreateConversation.call(
      sender: @alice,
      recipient_username: @bob.username,
      body: "Hello"
    )
    @conversation = result.value[:conversation]
    sign_in_as(@alice)
    Community::ArchiveConversation.call(user: @alice, conversation: @conversation)
  end

  test "archived conversation show page is accessible" do
    get forum_conversation_path(@conversation)

    assert_response :success
  end

  test "archived conversation appears in archived list" do
    get forum_conversations_path(archived: 1)

    assert_response :success
    assert_includes @response.body, @bob.username
  end
end

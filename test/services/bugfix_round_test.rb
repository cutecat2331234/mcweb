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
end

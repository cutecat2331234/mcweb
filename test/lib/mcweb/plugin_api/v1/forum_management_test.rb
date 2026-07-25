# frozen_string_literal: true

require "test_helper"
require "mcweb/plugin_api/v1/forum"

class Mcweb::PluginApi::V1::ForumManagementTest < ActiveSupport::TestCase
  setup do
    suffix = SecureRandom.hex(5)
    category = Community::Category.create!(
      name: "Plugin management #{suffix}",
      slug: "plugin-management-#{suffix}"
    )
    @section = Community::Section.create!(
      category:,
      name: "Plugin management",
      slug: "plugin-management-section-#{suffix}",
      position: 0
    )
    @author = create_user(forum_trust_level_override: 1)
    @answerer = create_user(forum_trust_level_override: 1)
    @invitee = create_user
    @moderator = create_user
    grant_permission(@moderator, "forum.topics.lock")
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @author,
      title: "Plugin management topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @answerer,
      replies_count: 1
    )
    Community::Post.create!(
      topic: @topic,
      user: @author,
      floor_number: 1,
      body: "Question",
      status: "published"
    )
    @answer = Community::Post.create!(
      topic: @topic,
      user: @answerer,
      floor_number: 2,
      body: "Answer",
      status: "published"
    )
    @forum = Mcweb::PluginApi::V1::Forum.new
  end

  test "plugins can solve and unsolve through core authorization services" do
    solved = @forum.mark_topic_solved(
      user: @author,
      topic_public_id: @topic.public_id,
      post_id: @answer.id
    )

    assert_predicate solved, :success?
    assert_equal @answer.id, solved.value.fetch("solved_post_id")
    assert_equal @answer.id, @topic.reload.solved_post_id

    unsolved = @forum.unsolve_topic(
      user: @author,
      topic_id: @topic.id
    )

    assert_predicate unsolved, :success?
    assert_nil unsolved.value.fetch("solved_post_id")
    assert_nil @topic.reload.solved_post_id
  end

  test "plugins can invite a watcher without bypassing topic ownership rules" do
    invited = @forum.invite_topic_watcher(
      user: @author,
      topic_id: @topic.id,
      username: @invitee.username
    )

    assert_predicate invited, :success?
    assert_equal "forum.topic_invite", invited.value.fetch("type")
    assert_equal @invitee.id, invited.value.fetch("user_id")
    assert Community::Subscription.exists?(user: @invitee, subscribable: @topic)

    denied = @forum.invite_topic_watcher(
      user: @answerer,
      topic_id: @topic.id,
      username: @invitee.username
    )
    assert_predicate denied, :failure?
    assert_equal "service_failure", denied.code
  end

  test "staff notes and topic reply bans keep granular core permissions" do
    denied_note = @forum.create_topic_staff_note(
      user: @author,
      topic_id: @topic.id,
      body: "Should not be visible"
    )
    assert_predicate denied_note, :failure?

    note = @forum.create_topic_staff_note(
      user: @moderator,
      topic_id: @topic.id,
      body: "Escalated for review"
    )
    assert_predicate note, :success?
    assert_equal "forum.topic_staff_note", note.value.fetch("type")
    assert_equal "Escalated for review", note.value.fetch("body")

    invalid_expiry = @forum.ban_topic_reply(
      user: @moderator,
      topic_id: @topic.id,
      target_username: @answerer.username,
      expires_at: 1.hour.ago
    )
    assert_predicate invalid_expiry, :failure?
    assert_equal "invalid_argument", invalid_expiry.code

    banned = @forum.ban_topic_reply(
      user: @moderator,
      topic_id: @topic.id,
      target_user_id: @answerer.id,
      reason: "Cooling-off period",
      expires_at: 1.day.from_now.iso8601
    )
    assert_predicate banned, :success?
    assert_equal true, banned.value.fetch("banned")
    assert_equal "Cooling-off period", banned.value.dig("ban", "reason")

    blocked_reply = Community::CreatePost.call(
      user: @answerer,
      topic: @topic,
      body: "This must be blocked",
      skip_interval_check: true
    )
    assert_predicate blocked_reply, :failure?

    unbanned = @forum.unban_topic_reply(
      user: @moderator,
      topic_public_id: @topic.public_id,
      target_username: @answerer.username
    )
    assert_predicate unbanned, :success?
    assert_equal false, unbanned.value.fetch("banned")
    refute Community::TopicReplyBan.exists?(topic: @topic, user: @answerer)

    allowed_reply = Community::CreatePost.call(
      user: @answerer,
      topic: @topic,
      body: "Posting is allowed again",
      skip_interval_check: true
    )
    assert_predicate allowed_reply, :success?
  end

  test "user selectors are exact and do not permit ambiguous targets" do
    ambiguous = @forum.ban_topic_reply(
      user: @moderator,
      topic_id: @topic.id,
      target_user_id: @answerer.id,
      target_username: @answerer.username
    )
    assert_predicate ambiguous, :failure?
    assert_equal "invalid_argument", ambiguous.code

    missing = @forum.unban_topic_reply(
      user: @moderator,
      topic_id: @topic.id,
      target_username: "missing-#{SecureRandom.hex(4)}"
    )
    assert_predicate missing, :failure?
    assert_equal "not_found", missing.code
  end
end

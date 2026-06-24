# frozen_string_literal: true

require "test_helper"

class ForumModerationAuditTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    grant_permission(@mod, "forum.topics.move")
    grant_permission(@mod, "forum.users.warn")
    grant_permission(@mod, "forum.users.mute")
    @target = create_user

    category = Community::Category.create!(name: "Cat", slug: "cat-#{SecureRandom.hex(3)}")
    @section = Community::Section.create!(category: category, name: "Sec", slug: "sec-#{SecureRandom.hex(3)}", position: 0)
    @other_section = Community::Section.create!(category: category, name: "Other", slug: "other-#{SecureRandom.hex(3)}", position: 1)
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(12)}",
      section: @section, user: @target, title: "Audited topic",
      status: "published", last_posted_at: Time.current, last_post_user: @target, replies_count: 0
    )
    @post = Community::Post.create!(topic: @topic, user: @target, floor_number: 1, body: "hello", status: "published")
  end

  test "locking a topic records an audit log entry" do
    assert_difference -> { AuditLog.where(action: "forum.topic.moderate").count }, 1 do
      result = Community::ModerateTopic.call(user: @mod, topic: @topic, action: "lock", lock_reason: "spam")
      assert result.success?, result.error
    end
    log = AuditLog.where(action: "forum.topic.moderate").order(:created_at).last
    assert_equal @mod.id, log.actor_id
    assert_equal "lock", log.metadata["moderation_action"]
    assert_equal "spam", log.reason
  end

  test "hiding a post records an audit log entry" do
    assert_difference -> { AuditLog.where(action: "forum.post.moderate").count }, 1 do
      assert Community::ModeratePost.call(user: @mod, post: @post, action: "hide").success?
    end
  end

  test "warning a user records an audit log entry" do
    assert_difference -> { AuditLog.where(action: "forum.user.warn").count }, 1 do
      assert Community::CreateUserWarning.call(actor: @mod, user: @target, reason: "rule break", points: 2).success?
    end
  end

  test "silencing a user records an audit log entry" do
    assert_difference -> { AuditLog.where(action: "forum.user.silence").count }, 1 do
      assert Community::CreateMute.call(actor: @mod, user: @target, reason: "cool off").success?
    end
  end

  test "moving a topic records an audit log entry" do
    assert_difference -> { AuditLog.where(action: "forum.topic.move").count }, 1 do
      assert Community::MoveTopic.call(user: @mod, topic: @topic, section: @other_section).success?
    end
  end
end

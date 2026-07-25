# frozen_string_literal: true

require "test_helper"

module Community
  class PendingPostModerationReliabilityTest < ActiveSupport::TestCase
    setup do
      category = Community::Category.create!(
        name: "Moderation reliability",
        slug: "moderation-reliability-#{SecureRandom.hex(4)}"
      )
      @section = Community::Section.create!(
        category: category,
        name: "Pending posts",
        slug: "pending-posts-#{SecureRandom.hex(4)}",
        position: 0
      )
      @moderator = create_user(username: "decisionmod#{SecureRandom.hex(3)}")
      Community::SectionModerator.create!(section: @section, user: @moderator)
      @author = create_user(username: "decisionauthor#{SecureRandom.hex(3)}")
      @topic = Community::Topic.create!(
        public_id: "topic_#{SecureRandom.alphanumeric(16)}",
        section: @section,
        user: @author,
        title: "Pending moderation decision",
        status: "hidden",
        last_posted_at: Time.current,
        last_post_user: @author,
        replies_count: 0
      )
      @post = Community::Post.create!(
        topic: @topic,
        user: @author,
        body: "Awaiting a moderator decision.",
        floor_number: 1,
        status: "pending_approval"
      )
    end

    test "a stale approval cannot reverse a completed rejection" do
      stale_post = Community::Post.find(@post.id)
      assert Community::RejectPost.call(actor: @moderator, post: @post, reason: "Off topic").success?

      approved_notifications = notification_count("forum.post_approved")
      approved_audits = audit_count("community.post_approved")

      result = Community::ApprovePost.call(actor: @moderator, post: stale_post)

      assert result.failure?
      assert_equal "hidden", @post.reload.status
      assert_equal "hidden", @topic.reload.status
      assert_equal approved_notifications, notification_count("forum.post_approved")
      assert_equal approved_audits, audit_count("community.post_approved")
    end

    test "a stale rejection cannot reverse a completed approval" do
      stale_post = Community::Post.find(@post.id)
      assert Community::ApprovePost.call(actor: @moderator, post: @post).success?

      rejected_notifications = notification_count("forum.post_rejected")
      rejected_audits = audit_count("community.post_rejected")

      result = Community::RejectPost.call(actor: @moderator, post: stale_post, reason: "Late rejection")

      assert result.failure?
      assert_equal "published", @post.reload.status
      assert_equal "published", @topic.reload.status
      assert_equal rejected_notifications, notification_count("forum.post_rejected")
      assert_equal rejected_audits, audit_count("community.post_rejected")
    end

    test "a duplicate stale approval does not repeat moderation side effects" do
      stale_post = Community::Post.find(@post.id)
      assert Community::ApprovePost.call(actor: @moderator, post: @post).success?

      approved_notifications = notification_count("forum.post_approved")
      approved_audits = audit_count("community.post_approved")

      result = Community::ApprovePost.call(actor: @moderator, post: stale_post)

      assert result.failure?
      assert_equal approved_notifications, notification_count("forum.post_approved")
      assert_equal approved_audits, audit_count("community.post_approved")
    end

    private

    def notification_count(type)
      Notification.where(user: @author, notification_type: type).count
    end

    def audit_count(action)
      AuditLog.for_resource(@post).by_action(action).count
    end
  end
end

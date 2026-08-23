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

    test "rejection requires a bounded reason before changing state" do
      blank = Community::RejectPost.call(actor: @moderator, post: @post, reason: " \n ")

      assert blank.failure?
      assert_equal "post_rejection_reason_required", blank.code
      assert_equal "pending_approval", @post.reload.status
      assert_equal 0, notification_count("forum.post_rejected")
      assert_equal 0, audit_count("community.post_rejected")

      too_long = Community::RejectPost.call(
        actor: @moderator,
        post: @post,
        reason: "x" * (Community::RejectPost::REASON_MAX_LENGTH + 1)
      )

      assert too_long.failure?
      assert_equal "post_rejection_reason_too_long", too_long.code
      assert_equal "pending_approval", @post.reload.status
      assert_equal 0, notification_count("forum.post_rejected")
      assert_equal 0, audit_count("community.post_rejected")
    end

    test "rejection persists the exact reason for the author and audit trail" do
      reason = "The reply contains an off-topic account advertisement."

      result = Community::RejectPost.call(actor: @moderator, post: @post, reason: reason)

      assert result.success?
      assert_equal "hidden", @post.reload.status
      notification = Notification.find_by!(user: @author, notification_type: "forum.post_rejected")
      assert_equal reason, notification.body
      audit = AuditLog.for_resource(@post).by_action("community.post_rejected").sole
      assert_equal reason, audit.reason
      assert_equal reason, audit.metadata.fetch("reason")
    end

    test "external rejection dispatch failure does not roll back the decision" do
      dispatch_failure = ServiceResult.failure(error: "forum_event_dispatch_unavailable")

      result = Community::DispatchForumEventWebhook.stub(:call, dispatch_failure) do
        Community::RejectPost.call(actor: @moderator, post: @post, reason: "Duplicate content")
      end

      assert result.success?
      assert_equal "hidden", @post.reload.status
      assert_equal 1, notification_count("forum.post_rejected")
      assert_equal 1, audit_count("community.post_rejected")
    end

    test "rejection validation codes are localized in supported locales" do
      %i[en zh-CN].each do |locale|
        I18n.with_locale(locale) do
          %w[post_rejection_reason_required post_rejection_reason_too_long].each do |code|
            refute_equal code, ServiceErrorTranslator.translate(code)
          end
        end
      end
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

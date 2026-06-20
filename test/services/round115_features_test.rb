# frozen_string_literal: true

require "test_helper"

class Round115ReplyDraftAttachmentTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "r115-reply") { |c| c.name = "R" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r115-reply-sec") { |s| s.name = "S"; s.position = 0 }
    @user = create_user
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Reply draft",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    Community::Post.create!(topic: @topic, user: @user, body: "OP", floor_number: 1, status: "published")
    @attachment = Community::PostAttachment.create!(
      user: @user,
      filename: "reply.txt",
      content_type: "text/plain",
      byte_size: 5
    )
    @attachment.file.attach(io: StringIO.new("hello"), filename: "reply.txt", content_type: "text/plain")
  end

  test "save reply draft stores attachment ids" do
    result = Community::SaveReplyDraft.call(
      user: @user,
      topic: @topic,
      body: "Draft reply",
      attachment_ids: [ @attachment.id ]
    )
    assert result.success?
    draft = Community::ReplyDraft.find_by!(user: @user, topic: @topic)
    assert_equal [ @attachment.id ], draft.attachment_id_list
  end

  test "save reply draft rejects invalid attachment ids" do
    other = create_user
    other_attachment = Community::PostAttachment.create!(
      user: other,
      filename: "other.txt",
      content_type: "text/plain",
      byte_size: 4
    )
    other_attachment.file.attach(io: StringIO.new("x"), filename: "other.txt", content_type: "text/plain")
    result = Community::SaveReplyDraft.call(
      user: @user,
      topic: @topic,
      body: "Draft",
      attachment_ids: [ other_attachment.id ]
    )
    assert result.failure?
  end
end

class Round115PostRestoredWebhookTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "r115-restore") { |c| c.name = "R" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r115-restore-sec") { |s| s.name = "S"; s.position = 0 }
    @mod = create_user(username: "r115restoremod")
    Community::SectionModerator.create!(section: @section, user: @mod)
    @user = create_user
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Restore webhook",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 1
    )
    Community::Post.create!(topic: @topic, user: @user, body: "OP", floor_number: 1, status: "published")
    @reply = Community::Post.create!(topic: @topic, user: @user, body: "Reply", floor_number: 2, status: "published")
    @reply.soft_delete!
    SiteSetting.set("forum.event_webhook_url", "https://example.com/forum-events")
    SiteSetting.set("forum.event_webhook_events", "post.restored")
  end

  test "restore post enqueues post.restored webhook" do
    assert_enqueued_with(job: Community::DispatchForumEventWebhookJob) do
      result = Community::RestorePost.call(actor: @mod, post: @reply)
      assert result.success?
    end
  end
end

class Round115PostRejectedWebhookTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "r115-reject") { |c| c.name = "R" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r115-reject-sec") { |s| s.name = "S"; s.position = 0 }
    @mod = create_user(username: "r115rejectmod")
    Community::SectionModerator.create!(section: @section, user: @mod)
    @author = create_user
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @author,
      title: "Reject webhook",
      status: "hidden",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    @post = Community::Post.create!(topic: @topic, user: @author, body: "Pending", floor_number: 1, status: "pending_approval")
    SiteSetting.set("forum.event_webhook_url", "https://example.com/forum-events")
    SiteSetting.set("forum.event_webhook_events", "post.rejected")
  end

  test "reject post enqueues post.rejected webhook and notification path" do
    assert_enqueued_with(job: Community::DispatchForumEventWebhookJob) do
      result = Community::RejectPost.call(actor: @mod, post: @post, reason: "spam")
      assert result.success?
    end
    notification = Notification.order(created_at: :desc).first
    assert_includes notification.metadata["path"], @topic.public_id
  end
end

class Round115AdminApprovalsSectionModTest < ActionDispatch::IntegrationTest
  setup do
    @mod = create_user(username: "r115adminmod", account_type: "staff")
    grant_permission(@mod, "admin.access")
    grant_admin_module(@mod, "forum")
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r115-admin") { |c| c.name = "A" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r115-admin-sec") { |s| s.name = "Sec"; s.position = 0 }
    @other_section = Community::Section.find_or_create_by!(category: category, slug: "r115-admin-other") { |s| s.name = "Other"; s.position = 1 }
    Community::SectionModerator.create!(section: @section, user: @mod)
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Admin pending",
      status: "hidden",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    @post = Community::Post.create!(topic: @topic, user: @user, body: "Wait", floor_number: 1, status: "pending_approval")
    @other_topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @other_section,
      user: @user,
      title: "Other pending",
      status: "hidden",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    @other_post = Community::Post.create!(topic: @other_topic, user: @user, body: "Other", floor_number: 1, status: "pending_approval")
  end

  test "section moderator with admin access sees scoped approvals" do
    sign_in_as(@mod)
    get admin_forum_approvals_path
    assert_response :success
    assert_includes response.body, "Admin pending"
    refute_includes response.body, "Other pending"
  end

  test "section moderator cannot approve post outside their section" do
    sign_in_as(@mod)
    post approve_admin_forum_approval_path(@other_post)
    assert_redirected_to admin_forum_approvals_path
    assert_equal "pending_approval", @other_post.reload.status
  end
end

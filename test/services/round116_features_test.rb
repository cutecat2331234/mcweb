# frozen_string_literal: true

require "test_helper"

class Round116PostApprovedWebhookTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "r116-approve") { |c| c.name = "R" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r116-approve-sec") { |s| s.name = "S"; s.position = 0 }
    @mod = create_user(username: "r116approvemod")
    Community::SectionModerator.create!(section: @section, user: @mod)
    @author = create_user
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @author,
      title: "Approve webhook",
      status: "hidden",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    @post = Community::Post.create!(topic: @topic, user: @author, body: "Pending OP", floor_number: 1, status: "pending_approval")
    SiteSetting.set("forum.event_webhook_url", "https://example.com/forum-events")
    SiteSetting.set("forum.event_webhook_events", "post.approved,post.created,topic.created")
  end

  test "approve post enqueues post.approved not topic.created" do
    assert_enqueued_jobs 1, only: Community::DispatchForumEventWebhookJob do
      result = Community::ApprovePost.call(actor: @mod, post: @post)
      assert result.success?
    end

    job = enqueued_jobs.find { |entry| entry[:job] == Community::DispatchForumEventWebhookJob }
    payload = job[:args][1]
    event = payload.is_a?(Hash) ? (payload["event"] || payload[:event]) : nil
    assert_equal "post.approved", event
  end

  test "approve post notifies author" do
    assert_difference -> { Notification.where(notification_type: "forum.post_approved").count }, 1 do
      Community::ApprovePost.call(actor: @mod, post: @post)
    end
    notification = Notification.order(created_at: :desc).first
    assert_equal @author.id, notification.user_id
    assert_includes notification.metadata["path"], @topic.public_id
  end
end

class Round116EditPostAttachmentsTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "r116-edit-att") { |c| c.name = "R" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r116-edit-att-sec") { |s| s.name = "S"; s.position = 0 }
    @user = create_user
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Edit attachments",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    @post = Community::Post.create!(topic: @topic, user: @user, body: "Original body long enough", floor_number: 1, status: "published")
    @attachment = Community::PostAttachment.create!(
      user: @user,
      filename: "edit.txt",
      content_type: "text/plain",
      byte_size: 4
    )
    @attachment.file.attach(io: StringIO.new("data"), filename: "edit.txt", content_type: "text/plain")
    SiteSetting.set("forum.event_webhook_url", "https://example.com/forum-events")
    SiteSetting.set("forum.event_webhook_events", "post.edited")
  end

  test "edit post links new attachment" do
    result = Community::EditPost.call(
      user: @user,
      post: @post,
      body: @post.body,
      attachment_ids: [ @attachment.id ]
    )
    assert result.success?
    assert_equal @post.id, @attachment.reload.forum_post_id
  end

  test "edit post unlinks removed attachment" do
    linked = Community::PostAttachment.create!(
      user: @user,
      forum_post_id: @post.id,
      filename: "old.txt",
      content_type: "text/plain",
      byte_size: 3
    )
    linked.file.attach(io: StringIO.new("old"), filename: "old.txt", content_type: "text/plain")

    result = Community::EditPost.call(
      user: @user,
      post: @post,
      body: @post.body,
      attachment_ids: []
    )
    assert result.success?
    assert_nil linked.reload.forum_post_id
  end

  test "attachment-only edit enqueues post.edited webhook" do
    assert_enqueued_with(job: Community::DispatchForumEventWebhookJob) do
      result = Community::EditPost.call(
        user: @user,
        post: @post,
        body: @post.body,
        attachment_ids: [ @attachment.id ]
      )
      assert result.success?
    end
  end
end

class Round116PendingPostAccessTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "r116-access") { |c| c.name = "R" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r116-access-sec") { |s| s.name = "S"; s.position = 0 }
    @mod = create_user(username: "r116accessmod")
    Community::SectionModerator.create!(section: @section, user: @mod)
    @author = create_user
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @author,
      title: "Pending access",
      status: "hidden",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    @post = Community::Post.create!(topic: @topic, user: @author, body: "Pending", floor_number: 1, status: "pending_approval")
  end

  test "section moderator can read pending post" do
    assert Community::PostAccess.readable?(post: @post, user: @mod)
  end

  test "section moderator can download pending post attachment" do
    attachment = Community::PostAttachment.create!(
      user: @author,
      forum_post_id: @post.id,
      filename: "pending.txt",
      content_type: "text/plain",
      byte_size: 4
    )
    attachment.file.attach(io: StringIO.new("file"), filename: "pending.txt", content_type: "text/plain")

    assert Community::PostAttachmentAccess.downloadable?(attachment, user: @mod)
  end
end

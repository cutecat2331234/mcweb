# frozen_string_literal: true

require "test_helper"

class Round114DeletePostWebhookTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "r114-del") { |c| c.name = "D" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r114-del-sec") { |s| s.name = "S"; s.position = 0 }
    @user = create_user
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Delete test",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 1
    )
    Community::Post.create!(topic: @topic, user: @user, body: "OP", floor_number: 1, status: "published")
    @reply = Community::Post.create!(topic: @topic, user: @user, body: "Reply", floor_number: 2, status: "published")
    @previous_url = SiteSetting.get("forum.event_webhook_url")
    @previous_events = SiteSetting.get("forum.event_webhook_events")
    SiteSetting.set("forum.event_webhook_url", "https://example.com/forum-events")
    SiteSetting.set("forum.event_webhook_events", "post.deleted")
  end

  teardown do
    SiteSetting.set("forum.event_webhook_url", @previous_url || "")
    SiteSetting.set("forum.event_webhook_events", @previous_events || Community::DispatchForumEventWebhook::DEFAULT_EVENTS)
  end

  test "delete post enqueues post.deleted webhook" do
    assert_enqueued_with(job: Community::DispatchForumEventWebhookJob) do
      result = Community::DeletePost.call(actor: @user, post: @reply)
      assert result.success?
    end
    assert @reply.reload.deleted_at.present?
  end

  test "cannot delete first post" do
    op = @topic.posts.find_by!(floor_number: 1)
    result = Community::DeletePost.call(actor: @user, post: op)
    assert result.failure?
  end
end

class Round114RestorePostSectionModTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "r114-restore") { |c| c.name = "R" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r114-restore-sec") { |s| s.name = "S"; s.position = 0 }
    @mod = create_user(username: "r114restoremod")
    @user = create_user
    Community::SectionModerator.create!(section: @section, user: @mod)
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Restore",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 1
    )
    Community::Post.create!(topic: @topic, user: @user, body: "OP", floor_number: 1, status: "published")
    @reply = Community::Post.create!(topic: @topic, user: @user, body: "Reply", floor_number: 2, status: "published")
    @reply.soft_delete!
  end

  test "section moderator can restore deleted post" do
    result = Community::RestorePost.call(actor: @mod, post: @reply)
    assert result.success?
    assert_nil @reply.reload.deleted_at
  end
end

class Round114DraftAttachmentTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "r114-draft") { |c| c.name = "D" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r114-draft-sec") { |s| s.name = "S"; s.position = 0 }
    @user = create_user
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Draft",
      status: "draft",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    @post = Community::Post.create!(topic: @topic, user: @user, body: "Draft body", floor_number: 1, status: "published")
    @attachment = Community::PostAttachment.create!(
      user: @user,
      filename: "draft.txt",
      content_type: "text/plain",
      byte_size: 12
    )
    @attachment.file.attach(io: StringIO.new("draft content"), filename: "draft.txt", content_type: "text/plain")
  end

  test "save topic draft links attachments" do
    result = Community::SaveTopicDraft.call(
      user: @user,
      section: @section,
      title: "Draft",
      body: "Draft body",
      topic: @topic,
      attachment_ids: [ @attachment.id ]
    )
    assert result.success?
    assert_equal @post.id, @attachment.reload.forum_post_id
  end

  test "publish topic draft keeps linked attachments" do
    Community::LinkPostAttachments.call(user: @user, post: @post, attachment_ids: [ @attachment.id ])
    result = Community::PublishTopicDraft.call(user: @user, topic: @topic)
    assert result.success?
    assert_equal "published", @topic.reload.status
    assert_equal @post.id, @attachment.reload.forum_post_id
  end
end

class Round114ScheduleTopicAttachmentTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "r114-sched") { |c| c.name = "S" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r114-sched-sec") { |s| s.name = "Sec"; s.position = 0 }
    @user = create_user
    @attachment = Community::PostAttachment.create!(
      user: @user,
      filename: "sched.txt",
      content_type: "text/plain",
      byte_size: 8
    )
    @attachment.file.attach(io: StringIO.new("schedule"), filename: "sched.txt", content_type: "text/plain")
  end

  test "schedule topic links attachments to opening post" do
    result = Community::ScheduleTopic.call(
      user: @user,
      section: @section,
      title: "Scheduled",
      body: "Later",
      scheduled_at: 2.hours.from_now,
      attachment_ids: [ @attachment.id ]
    )
    assert result.success?
    post = result.value.posts.first
    assert_equal post.id, @attachment.reload.forum_post_id
  end
end

class Round114PendingPostsScopeTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "r114-pending") { |c| c.name = "P" }
    @section_a = Community::Section.find_or_create_by!(category: category, slug: "r114-pend-a") { |s| s.name = "A"; s.position = 0 }
    @section_b = Community::Section.find_or_create_by!(category: category, slug: "r114-pend-b") { |s| s.name = "B"; s.position = 1 }
    @mod = create_user(username: "r114pendingmod")
    Community::SectionModerator.create!(section: @section_a, user: @mod)
    @author = create_user
    @topic_a = create_topic_with_pending(@section_a, "Topic A")
    @topic_b = create_topic_with_pending(@section_b, "Topic B")
  end

  test "section moderator pending scope only includes moderated sections" do
    scope = Community::SectionModeration.pending_posts_scope_for(@mod)
    topic_ids = scope.map(&:forum_topic_id)
    assert_includes topic_ids, @topic_a.id
    refute_includes topic_ids, @topic_b.id
  end

  private

  def create_topic_with_pending(section, title)
    topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @author,
      title: title,
      status: "hidden",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    Community::Post.create!(topic: topic, user: @author, body: "Pending", floor_number: 1, status: "pending_approval")
    topic
  end
end

class Round114ModerationApprovalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @mod = create_user(username: "r114modctrl")
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r114-ctrl") { |c| c.name = "C" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r114-ctrl-sec") { |s| s.name = "Sec"; s.position = 0 }
    Community::SectionModerator.create!(section: @section, user: @mod)
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Pending ctrl",
      status: "hidden",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    @post = Community::Post.create!(topic: @topic, user: @user, body: "Wait", floor_number: 1, status: "pending_approval")
  end

  test "section moderator can access moderation approvals index" do
    sign_in_as(@mod)
    get forum_moderation_approvals_path
    assert_response :success
    assert_includes response.body, "Pending ctrl"
  end

  test "regular user cannot access moderation approvals index" do
    sign_in_as(@user)
    get forum_moderation_approvals_path
    assert_redirected_to forum_latest_path
  end
end

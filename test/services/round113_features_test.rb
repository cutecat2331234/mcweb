# frozen_string_literal: true

require "test_helper"

class Round113SectionModeratorPermissionsTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "r113-perm") { |c| c.name = "P" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r113-sec-a") do |s|
      s.name = "Section A"
      s.position = 0
    end
    @other_section = Community::Section.find_or_create_by!(category: category, slug: "r113-sec-b") do |s|
      s.name = "Section B"
      s.position = 1
    end
    @mod = create_user(username: "r113sectionmod")
    @user = create_user(username: "r113author")
    @other = create_user(username: "r113other")
    Community::SectionModerator.create!(section: @section, user: @mod)
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Permissions topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    @post = Community::Post.create!(topic: @topic, user: @user, body: "OP body", floor_number: 1, status: "published")
    @reply = Community::Post.create!(topic: @topic, user: @other, body: "Reply body", floor_number: 2, status: "published")
  end

  test "section moderator can edit others post" do
    assert Community::EditPost.editable_by?(@mod, @reply)
    result = Community::EditPost.call(user: @mod, post: @reply, body: "Moderated edit")
    assert result.success?
  end

  test "section moderator can edit topic title" do
    result = Community::EditTopic.call(user: @mod, topic: @topic, title: "New title by mod")
    assert result.success?
    assert_equal "New title by mod", @topic.reload.title
  end

  test "section moderator can mark topic solved" do
    result = Community::MarkTopicSolved.call(user: @mod, topic: @topic, post: @reply)
    assert result.success?
    assert_equal @reply.id, @topic.reload.solved_post_id
  end

  test "section moderator can unsolve topic" do
    @topic.update!(solved_post: @reply)
    result = Community::UnsolveTopic.call(user: @mod, topic: @topic)
    assert result.success?
    assert_nil @topic.reload.solved_post_id
  end

  test "section moderator can move topic within moderated sections" do
    Community::SectionModerator.create!(section: @other_section, user: @mod)
    result = Community::MoveTopic.call(user: @mod, topic: @topic, section: @other_section)
    assert result.success?
    assert_equal @other_section.id, @topic.reload.forum_section_id
  end

  test "section moderator cannot move topic to unmoderated section" do
    result = Community::MoveTopic.call(user: @mod, topic: @topic, section: @other_section)
    assert result.failure?
    assert_equal @section.id, @topic.reload.forum_section_id
  end

  test "regular user cannot use section moderator powers" do
    refute Community::EditPost.editable_by?(@other, @post)
    refute Community::SectionModeration.can_mark_solved?(user: @other, topic: @topic)
  end
end

class Round113TopicMovedWebhookTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "r113-move") { |c| c.name = "M" }
    @from = Community::Section.find_or_create_by!(category: category, slug: "r113-from") { |s| s.name = "From"; s.position = 0 }
    @to = Community::Section.find_or_create_by!(category: category, slug: "r113-to") { |s| s.name = "To"; s.position = 1 }
    @mod = create_user
    Community::SectionModerator.create!(section: @from, user: @mod)
    Community::SectionModerator.create!(section: @to, user: @mod)
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @from,
      user: @mod,
      title: "Move me",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @mod,
      replies_count: 0
    )
    @previous_url = SiteSetting.get("forum.event_webhook_url")
    @previous_events = SiteSetting.get("forum.event_webhook_events")
    SiteSetting.set("forum.event_webhook_url", "https://example.com/forum-events")
    SiteSetting.set("forum.event_webhook_events", "topic.moved")
  end

  teardown do
    SiteSetting.set("forum.event_webhook_url", @previous_url || "")
    SiteSetting.set("forum.event_webhook_events", @previous_events || Community::DispatchForumEventWebhook::DEFAULT_EVENTS)
  end

  test "move topic enqueues topic.moved webhook" do
    assert_enqueued_with(job: Community::DispatchForumEventWebhookJob) do
      Community::MoveTopic.call(user: @mod, topic: @topic, section: @to)
    end
  end
end

class Round113RetryForumEventWebhooksJobTest < ActiveSupport::TestCase
  test "requeues stale pending event webhook deliveries" do
    delivery = Community::EventWebhookDelivery.create!(
      event_type: "post.created",
      url: "https://example.com/hook",
      status: "pending",
      request_payload: { event: "post.created", test: true },
      attempt_count: 1,
      created_at: 10.minutes.ago
    )

    assert_enqueued_with(job: Community::DispatchForumEventWebhookJob) do
      Community::RetryFailedForumEventWebhooksJob.perform_now
    end

    assert_equal 2, delivery.reload.attempt_count
  end
end

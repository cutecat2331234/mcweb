# frozen_string_literal: true

require "test_helper"

class Round112SectionModeratorModerateTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "r112-mod") { |c| c.name = "M" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r112-mod-sec") do |s|
      s.name = "Mod Section"
      s.position = 0
    end
    @other_section = Community::Section.find_or_create_by!(category: category, slug: "r112-other-sec") do |s|
      s.name = "Other"
      s.position = 1
    end
    @mod = create_user(username: "r112sectionmod")
    @user = create_user
    Community::SectionModerator.create!(section: @section, user: @mod)
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Lock me",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    Community::Post.create!(topic: @topic, user: @user, body: "OP", floor_number: 1, status: "published")
    @other_topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @other_section,
      user: @user,
      title: "Other",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    Community::Post.create!(topic: @other_topic, user: @user, body: "OP", floor_number: 1, status: "published")
  end

  test "section moderator can lock topic in their section" do
    result = Community::ModerateTopic.call(user: @mod, topic: @topic, action: "lock")
    assert result.success?
    assert @topic.reload.locked?
  end

  test "section moderator cannot lock topic in other section" do
    result = Community::ModerateTopic.call(user: @mod, topic: @other_topic, action: "lock")
    assert result.failure?
  end

  test "section moderator cannot set global announcement" do
    result = Community::ModerateTopic.call(user: @mod, topic: @topic, action: "global_announcement")
    assert result.failure?
  end

  test "bulk moderate only processes authorized topics" do
    result = Community::BulkModerateTopics.call(
      user: @mod,
      topic_public_ids: [ @topic.public_id, @other_topic.public_id ],
      action: "lock"
    )
    assert result.success?
    assert_equal 1, result.value[:moderated]
    assert_equal 1, result.value[:failed]
    assert @topic.reload.locked?
    refute @other_topic.reload.locked?
  end
end

class Round112ForumEventWebhookTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "r112-hook") { |c| c.name = "H" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r112-hook-sec") do |s|
      s.name = "Hook"
      s.position = 0
    end
    @user = create_user
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @user,
      title: "Webhook topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    @post = Community::Post.create!(topic: @topic, user: @user, body: "Hello webhook", floor_number: 1, status: "published")
    @previous_url = SiteSetting.get("forum.event_webhook_url")
    @previous_events = SiteSetting.get("forum.event_webhook_events")
    SiteSetting.set("forum.event_webhook_url", "https://example.com/forum-events")
    SiteSetting.set("forum.event_webhook_events", "topic.created,post.created,post.edited,topic.solved")
  end

  teardown do
    SiteSetting.set("forum.event_webhook_url", @previous_url || "")
    SiteSetting.set("forum.event_webhook_events", @previous_events || Community::DispatchForumEventWebhook::DEFAULT_EVENTS)
  end

  test "publish post side effects enqueues topic.created webhook" do
    assert_enqueued_with(job: Community::DispatchForumEventWebhookJob) do
      Community::DispatchForumEventWebhook.call(event_type: "topic.created", topic: @topic, post: @post)
    end
  end

  test "dispatch skips disabled events" do
    SiteSetting.set("forum.event_webhook_events", "post.created")
    result = Community::DispatchForumEventWebhook.call(event_type: "topic.created", topic: @topic, post: @post)
    assert result.success?
    assert_equal :event_disabled, result.value[:skipped]
  end

  test "build payload includes topic and post" do
    result = Community::BuildForumEventWebhookPayload.call(event_type: "post.created", topic: @topic, post: @post)
    assert result.success?
    assert_equal "post.created", result.value[:event]
    assert_equal @topic.public_id, result.value.dig(:topic, :id)
    assert_equal @post.id, result.value.dig(:post, :id)
  end

  test "test event webhook enqueues job" do
    assert_enqueued_with(job: Community::DispatchForumEventWebhookJob) do
      result = Community::DispatchTestForumEventWebhook.call(event_type: "topic.created")
      assert result.success?
    end
  end

  test "edit post dispatches post.edited webhook" do
    assert_enqueued_with(job: Community::DispatchForumEventWebhookJob) do
      Community::EditPost.call(user: @user, post: @post, body: "Edited body for webhook test")
    end
  end

  test "mark solved dispatches topic.solved webhook" do
    reply = Community::Post.create!(topic: @topic, user: @user, body: "solution", floor_number: 2, status: "published")
    assert_enqueued_with(job: Community::DispatchForumEventWebhookJob) do
      Community::MarkTopicSolved.call(user: @user, topic: @topic, post: reply)
    end
  end
end

class Round112ForumEventWebhookJobTest < ActiveSupport::TestCase
  test "job records failed delivery for unreachable url" do
    payload = {
      "event" => "topic.created",
      "topic" => { "id" => "test_topic", "title" => "T" },
      "test" => true
    }
    assert_difference -> { Community::EventWebhookDelivery.count }, 1 do
      Community::DispatchForumEventWebhookJob.perform_now("http://127.0.0.1:1/invalid", payload)
    end
    delivery = Community::EventWebhookDelivery.last
    assert_equal "failed", delivery.status
    assert_equal "topic.created", delivery.event_type
  end
end

# frozen_string_literal: true

require "test_helper"

class Community::ContentIdempotencyTest < ActiveSupport::TestCase
  parallelize(workers: 1)

  setup do
    suffix = SecureRandom.hex(5)
    category = Community::Category.create!(
      name: "Idempotency #{suffix}",
      slug: "idempotency-#{suffix}"
    )
    @section = Community::Section.create!(
      category: category,
      name: "Idempotency",
      slug: "idempotency-#{suffix}",
      position: 0
    )
    @author = create_user(username: "idempotency_author_#{suffix}")
    @topic_owner = create_user(username: "idempotency_owner_#{suffix}")
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @topic_owner,
      title: "Existing idempotency topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @topic_owner,
      replies_count: 0
    )
    Community::Post.create!(
      topic: @topic,
      user: @topic_owner,
      floor_number: 1,
      body: "Opening post",
      status: "published"
    )
    SiteSetting.set("forum.event_webhook_url", "https://example.com/forum-events")
    SiteSetting.set("forum.event_webhook_events", "topic.created,post.created")
  end

  test "replaying a topic request returns the original topic without duplicate side effects" do
    key = "topic-#{SecureRandom.uuid}"
    title = "Idempotent topic #{SecureRandom.hex(3)}"
    first = nil
    replay = nil

    assert_difference -> { Community::Topic.count }, 1 do
      assert_difference -> { Community::Post.count }, 1 do
        assert_difference -> { Community::ContentRequest.count }, 1 do
          first = Community::CreateTopic.call(
            user: @author,
            section: @section,
            title: title,
            body: "Created exactly once.",
            idempotency_key: key
          )
          replay = Community::CreateTopic.call(
            user: @author,
            section: @section,
            title: title,
            body: "Created exactly once.",
            idempotency_key: key
          )
        end
      end
    end

    assert_predicate first, :success?
    assert_predicate replay, :success?
    assert_equal first.value.id, replay.value.id
    assert_equal 1, AuditLog.where(action: "community.topic_created", resource_id: first.value.id).count
    assert_equal 1, forum_webhook_jobs_for("topic.created").size
  end

  test "replaying a reply request returns the original post without duplicate side effects" do
    key = "post-#{SecureRandom.uuid}"
    first = nil
    replay = nil

    assert_difference -> { Community::Post.count }, 1 do
      assert_difference -> { Community::ContentRequest.count }, 1 do
        first = Community::CreatePost.call(
          user: @author,
          topic: @topic,
          body: "Idempotent reply.",
          skip_interval_check: true,
          idempotency_key: key
        )
        replay = Community::CreatePost.call(
          user: @author,
          topic: @topic,
          body: "Idempotent reply.",
          skip_interval_check: true,
          idempotency_key: key
        )
      end
    end

    assert_predicate first, :success?
    assert_predicate replay, :success?
    assert_equal first.value.id, replay.value.id
    assert_equal 1, AuditLog.where(action: "community.post_created", resource_id: first.value.id).count
    assert_equal 1, forum_webhook_jobs_for("post.created").size
    assert_equal 1,
      Community::PointTransaction.where(reason: "post_created", source: first.value).count
  end

  test "reusing a request key for different content is rejected" do
    key = "mismatch-#{SecureRandom.uuid}"
    first = Community::CreateTopic.call(
      user: @author,
      section: @section,
      title: "Original request #{SecureRandom.hex(3)}",
      body: "Original body.",
      idempotency_key: key
    )
    assert_predicate first, :success?

    assert_no_difference -> { Community::Topic.count } do
      result = Community::CreateTopic.call(
        user: @author,
        section: @section,
        title: "Changed request #{SecureRandom.hex(3)}",
        body: "Changed body.",
        idempotency_key: key
      )

      assert_predicate result, :failure?
      assert_equal I18n.t("mcweb.services.errors.idempotency_key_reused"), result.error
    end
  end

  test "invalid request keys fail before creating content" do
    assert_no_difference -> { Community::Post.count } do
      assert_no_difference -> { Community::ContentRequest.count } do
        result = Community::CreatePost.call(
          user: @author,
          topic: @topic,
          body: "Invalid key reply.",
          skip_interval_check: true,
          idempotency_key: "invalid key with spaces"
        )

        assert_predicate result, :failure?
        assert_equal I18n.t("mcweb.services.errors.idempotency_key_invalid"), result.error
      end
    end
  end

  test "request fingerprints are stable across hash key order" do
    first = Community::ContentIdempotency.fingerprint(
      title: "Stable",
      nested: { "b" => 2, "a" => 1 }
    )
    second = Community::ContentIdempotency.fingerprint(
      nested: { "a" => 1, "b" => 2 },
      title: "Stable"
    )

    assert_equal first, second
  end

  test "concurrent reply retries create one post and return the same resource" do
    key = "concurrent-#{SecureRandom.uuid}"
    body = "Concurrent idempotent reply."
    ready = Queue.new
    start = Queue.new

    threads = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          user = User.find(@author.id)
          topic = Community::Topic.find(@topic.id)
          ready << true
          start.pop
          Community::CreatePost.call(
            user: user,
            topic: topic,
            body: body,
            skip_interval_check: true,
            idempotency_key: key
          )
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    results = threads.map(&:value)

    assert results.all?(&:success?), results.map(&:error).inspect
    assert_equal 1, Community::Post.where(user: @author, topic: @topic, body: body).count
    assert_equal 1,
      Community::ContentRequest.where(user: @author, operation: "post.create").count
    assert_equal 1, results.map { |result| result.value.id }.uniq.size
  end

  private

  def forum_webhook_jobs_for(event)
    enqueued_jobs.select do |job|
      next false unless job[:job] == Community::DispatchForumEventWebhookJob

      payload = job[:args][1]
      (payload.is_a?(Hash) ? payload["event"] || payload[:event] : nil) == event
    end
  end
end

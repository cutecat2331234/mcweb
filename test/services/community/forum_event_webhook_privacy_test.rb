# frozen_string_literal: true

require "test_helper"

module Community
  class ForumEventWebhookPrivacyTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    FakeResponse = Data.define(:code, :body)

    setup do
      suffix = SecureRandom.hex(4)
      category = Community::Category.create!(
        name: "Webhook privacy",
        slug: "webhook-privacy-#{suffix}"
      )
      @public_section = Community::Section.create!(
        category: category,
        name: "SECTION_SENTINEL_#{suffix}",
        slug: "webhook-public-#{suffix}",
        position: 0
      )
      @private_section = Community::Section.create!(
        category: category,
        name: "PRIVATE_SECTION_SENTINEL_#{suffix}",
        slug: "webhook-private-#{suffix}",
        position: 1,
        login_required: true
      )
      @author = create_user(username: "webhook_sentinel_#{suffix}")
      @public_topic, @public_post = create_topic_and_post(
        @public_section,
        title: "TITLE_SENTINEL_#{suffix}",
        body: "BODY_SENTINEL_#{suffix}"
      )
      @private_topic, @private_post = create_topic_and_post(
        @private_section,
        title: "PRIVATE_TITLE_SENTINEL_#{suffix}",
        body: "PRIVATE_BODY_SENTINEL_#{suffix}"
      )
      @whisper = Community::Post.create!(
        topic: @public_topic,
        user: @author,
        floor_number: 2,
        body: "WHISPER_SENTINEL_#{suffix}",
        status: "published",
        post_type: "whisper"
      )
      @previous_url = SiteSetting.get("forum.event_webhook_url")
      @previous_events = SiteSetting.get("forum.event_webhook_events")
      SiteSetting.set("forum.event_webhook_url", "https://example.com/forum-events")
      SiteSetting.set("forum.event_webhook_events", Community::DispatchForumEventWebhook::DEFAULT_EVENTS)
    end

    teardown do
      SiteSetting.set("forum.event_webhook_url", @previous_url || "")
      SiteSetting.set(
        "forum.event_webhook_events",
        @previous_events || Community::DispatchForumEventWebhook::DEFAULT_EVENTS
      )
    end

    test "builder emits an identifier-only invalidation and ignores arbitrary extras" do
      result = Community::BuildForumEventWebhookPayload.call(
        event_type: "post.edited",
        topic: @public_topic,
        post: @public_post,
        extra: {
          reason: "REASON_SENTINEL",
          approved_by_username: "MODERATOR_SENTINEL",
          nested: { body: "NESTED_SENTINEL" }
        }
      )

      assert_predicate result, :success?
      assert_equal %i[event occurred_at post topic], result.value.keys.sort
      assert_equal({ id: @public_topic.public_id }, result.value[:topic])
      assert_equal({ id: @public_post.id }, result.value[:post])
      assert_minimal_payload(result.value)
    end

    test "private sections and whispers never enqueue either outbound webhook path" do
      Administration::WebhookSubscription.create!(
        name: "privacy wildcard",
        url: "https://example.com/generic-hook",
        event: "*"
      )

      assert_no_enqueued_jobs only: [
        Community::DispatchForumEventWebhookJob,
        Administration::DeliverWebhookSubscriptionJob
      ] do
        private_result = Community::DispatchForumEventWebhook.call(
          event_type: "post.edited",
          topic: @private_topic,
          post: @private_post,
          extra: { reason: "PRIVATE_REASON_SENTINEL" }
        )
        whisper_result = Community::DispatchForumEventWebhook.call(
          event_type: "post.edited",
          topic: @public_topic,
          post: @whisper,
          extra: { reason: "WHISPER_REASON_SENTINEL" }
        )

        assert_equal :private_forum_resource, private_result.value[:skipped]
        assert_equal :private_forum_resource, whisper_result.value[:skipped]
      end
    end

    test "rejected posts never enqueue either outbound webhook path" do
      Administration::WebhookSubscription.create!(
        name: "rejected privacy wildcard",
        url: "https://example.com/generic-hook",
        event: "*"
      )

      assert_no_enqueued_jobs only: [
        Community::DispatchForumEventWebhookJob,
        Administration::DeliverWebhookSubscriptionJob
      ] do
        result = Community::DispatchForumEventWebhook.call(
          event_type: "post.rejected",
          topic: @public_topic,
          post: @public_post,
          extra: { reason: "REJECTED_REASON_SENTINEL" }
        )

        assert_equal :private_forum_resource, result.value[:skipped]
      end
    end

    test "pending or rejected regular posts do not become exportable when deleted" do
      pending = Community::Post.create!(
        topic: @public_topic,
        user: @author,
        floor_number: 3,
        body: "PENDING_DELETE_SENTINEL",
        status: "pending_approval",
        post_type: "regular"
      )
      rejected = Community::Post.create!(
        topic: @public_topic,
        user: @author,
        floor_number: 4,
        body: "REJECTED_DELETE_SENTINEL",
        status: "hidden",
        post_type: "regular"
      )
      pending.soft_delete!
      rejected.soft_delete!
      Administration::WebhookSubscription.create!(
        name: "deleted moderation wildcard",
        url: "https://example.com/generic-hook",
        event: "*"
      )

      assert_no_enqueued_jobs only: [
        Community::DispatchForumEventWebhookJob,
        Administration::DeliverWebhookSubscriptionJob
      ] do
        [ pending, rejected ].each do |post|
          result = Community::DispatchForumEventWebhook.call(
            event_type: "post.deleted",
            topic: @public_topic,
            post: post
          )
          assert_equal :private_forum_resource, result.value[:skipped]
        end
      end

      bodies = []
      with_public_webhook_transport(bodies) do
        assert_no_difference -> { Community::EventWebhookDelivery.count } do
          [ pending, rejected ].each do |post|
            Community::DispatchForumEventWebhookJob.perform_now(
              "https://example.com/forum-events",
              {
                event: "post.deleted",
                topic: { id: @public_topic.public_id },
                post: { id: post.id, body_excerpt: post.body }
              }
            )
          end
        end
      end
      assert_empty bodies
    end

    test "reports and warnings never cross the generic outbound boundary" do
      subscription = Administration::WebhookSubscription.create!(
        name: "moderation metadata wildcard",
        url: "https://example.com/generic-hook",
        event: "*"
      )

      assert_no_enqueued_jobs only: Administration::DeliverWebhookSubscriptionJob do
        Mcweb::Events.publish(
          "forum.report.created",
          reportable: @public_post,
          reporter: @author
        )
        Mcweb::Events.publish(
          "forum.warning.issued",
          user: @author,
          actor: @author
        )
      end

      bodies = []
      with_public_webhook_transport(bodies) do
        %w[forum.report.created forum.warning.issued].each do |event|
          payload = Administration::SerializeEventPayload.call(
            event: event,
            payload: {
              reportable: @public_post,
              user: @author,
              actor: @author
            }
          )
          Administration::DeliverWebhookSubscriptionJob.perform_now(
            subscription.id,
            payload
          )
        end
      end
      assert_empty bodies
      assert_equal 0, subscription.reload.failure_count
    end

    test "dedicated job rechecks privacy after enqueue and blocks legacy rejected events" do
      bodies = []
      payload = Community::BuildForumEventWebhookPayload.call(
        event_type: "post.edited",
        topic: @public_topic,
        post: @public_post
      ).value
      rejected_payload = payload.deep_stringify_keys.merge(
        "event" => "post.rejected",
        "reason" => "REJECTED_QUEUE_SENTINEL",
        "post" => {
          "id" => @public_post.id,
          "body_excerpt" => "REJECTED_BODY_SENTINEL"
        }
      )

      with_public_webhook_transport(bodies) do
        assert_no_difference -> { Community::EventWebhookDelivery.count } do
          Community::DispatchForumEventWebhookJob.perform_now(
            "https://example.com/forum-events",
            rejected_payload
          )
          @public_section.update!(login_required: true)
          Community::DispatchForumEventWebhookJob.perform_now(
            "https://example.com/forum-events",
            payload
          )
        end
      end

      assert_empty bodies
    end

    test "generic delivery job rechecks current forum privacy" do
      subscription = Administration::WebhookSubscription.create!(
        name: "queued generic privacy",
        url: "https://example.com/generic-hook",
        event: "forum.post.edited"
      )
      payload = Administration::SerializeEventPayload.call(
        event: "forum.post.edited",
        payload: { topic: @public_topic, post: @public_post }
      )
      bodies = []
      @public_section.update!(login_required: true)

      with_public_webhook_transport(bodies) do
        Administration::DeliverWebhookSubscriptionJob.perform_now(
          subscription.id,
          payload
        )
      end

      assert_empty bodies
      assert_equal 0, subscription.reload.failure_count
    end

    test "dedicated queue arguments never contain the signing secret" do
      previous_secret = SiteSetting.get("forum.event_webhook_secret")
      sentinel = "QUEUE_SECRET_SENTINEL_#{SecureRandom.hex(8)}"
      SiteSetting.set("forum.event_webhook_secret", sentinel)
      clear_enqueued_jobs

      result = Community::DispatchForumEventWebhook.call(
        event_type: "post.edited",
        topic: @public_topic,
        post: @public_post
      )

      assert_predicate result, :success?
      queued = enqueued_jobs.find do |job|
        job[:job] == Community::DispatchForumEventWebhookJob
      end
      assert queued
      refute_includes queued.fetch(:args).to_json, sentinel
    ensure
      SiteSetting.set("forum.event_webhook_secret", previous_secret || "")
    end

    test "job strips legacy rich content before persistence and delivery" do
      bodies = []
      legacy_payload = {
        "event" => "post.edited",
        "occurred_at" => Time.current.iso8601,
        "topic" => {
          "id" => @public_topic.public_id,
          "title" => @public_topic.title,
          "section_name" => @public_section.name
        },
        "post" => {
          "id" => @public_post.id,
          "username" => @author.username,
          "body_excerpt" => @public_post.body
        },
        "reason" => "EDIT_REASON_SENTINEL"
      }

      with_public_webhook_transport(bodies) do
        assert_difference -> { Community::EventWebhookDelivery.count }, 1 do
          Community::DispatchForumEventWebhookJob.perform_now(
            "https://example.com/forum-events",
            legacy_payload
          )
        end
      end

      delivery = Community::EventWebhookDelivery.order(:id).last
      assert_equal "success", delivery.status
      assert_equal 1, bodies.size
      assert_equal delivery.request_payload, JSON.parse(bodies.first)
      assert_minimal_payload(delivery.request_payload)
    end

    test "model and admin retry scrub legacy request payloads before requeue" do
      delivery = Community::EventWebhookDelivery.create!(
        event_type: "post.deleted",
        topic: @public_topic,
        post: @public_post,
        url: "https://example.com/forum-events",
        status: "failed",
        request_payload: {
          event: "post.deleted",
          topic: { id: @public_topic.public_id, title: "MODEL_TITLE_SENTINEL" },
          post: { id: @public_post.id, body_excerpt: "MODEL_BODY_SENTINEL" }
        }
      )
      assert_minimal_payload(delivery.reload.request_payload)

      delivery.update_column(
        :request_payload,
        {
          event: "post.deleted",
          topic: { id: @public_topic.public_id, title: "LEGACY_TITLE_SENTINEL" },
          post: { id: @public_post.id, body_excerpt: "LEGACY_BODY_SENTINEL" },
          reason: "LEGACY_REASON_SENTINEL"
        }
      )

      with_singleton_method(UrlSafety, :public_http_url?, ->(*) { true }) do
        assert_enqueued_with(job: Community::DispatchForumEventWebhookJob) do
          result = Community::AdminRetryForumEventWebhook.call(delivery: delivery.reload)
          assert_predicate result, :success?
        end
      end

      assert_minimal_payload(delivery.reload.request_payload)
      queued = enqueued_jobs.find { |job| job[:job] == Community::DispatchForumEventWebhookJob }
      assert_minimal_payload(queued.fetch(:args))
    end

    test "admin retry fails closed when the resource became private" do
      delivery = Community::EventWebhookDelivery.create!(
        event_type: "post.edited",
        topic: @public_topic,
        post: @public_post,
        url: "https://example.com/forum-events",
        status: "failed",
        request_payload: {
          event: "post.edited",
          topic: { id: @public_topic.public_id },
          post: { id: @public_post.id }
        }
      )
      @public_section.update!(login_required: true)

      assert_no_enqueued_jobs only: Community::DispatchForumEventWebhookJob do
        result = Community::AdminRetryForumEventWebhook.call(delivery: delivery)
        assert_predicate result, :failure?
        assert_equal "webhook_private_forum_resource", result.error
      end
      assert_equal "blocked: private forum resource", delivery.reload.response_body
      assert_minimal_payload(delivery.request_payload)
    end

    test "generic serializer exports only stable record identifiers" do
      payload = Administration::SerializeEventPayload.call(
        event: "forum.post.created",
        payload: {
          topic: @public_topic,
          post: @public_post,
          user: @author,
          reason: "GENERIC_REASON_SENTINEL",
          metadata: { body: "GENERIC_BODY_SENTINEL" }
        }
      )

      assert_equal({ "id" => @public_topic.public_id }, payload.dig("data", "topic"))
      assert_equal(
        { "id" => @public_post.id, "topic_id" => @public_topic.public_id },
        payload.dig("data", "post")
      )
      assert_equal({ "id" => @author.public_id }, payload.dig("data", "user"))
      assert_minimal_payload(payload)
    end

    private

    def create_topic_and_post(section, title:, body:)
      topic = Community::Topic.create!(
        section: section,
        user: @author,
        title: title,
        status: "published",
        last_posted_at: Time.current,
        last_post_user: @author,
        replies_count: 0
      )
      post = Community::Post.create!(
        topic: topic,
        user: @author,
        floor_number: 1,
        body: body,
        status: "published"
      )
      [ topic, post ]
    end

    def assert_minimal_payload(payload)
      serialized = payload.to_json
      refute_match(
        /SENTINEL|title|body|excerpt|section_(?:name|slug)|username|reason|path|floor_number|user_id/i,
        serialized
      )
    end

    def with_public_webhook_transport(bodies, &)
      poster = lambda do |_uri, body:, **_options|
        bodies << body
        FakeResponse.new(code: "204", body: "")
      end
      with_singleton_method(UrlSafety, :public_http_url?, ->(*) { true }) do
        with_singleton_method(UrlSafety, :safe_http_post, poster, &)
      end
    end

    def with_singleton_method(object, method_name, replacement)
      original = object.method(method_name)
      object.define_singleton_method(method_name, replacement)
      yield
    ensure
      object.define_singleton_method(method_name, original)
    end
  end
end

class AdminForumEventWebhookSettingsPrivacyTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
    sign_in_as(@admin)
    @previous_url = SiteSetting.get("forum.event_webhook_url")
    @previous_events = SiteSetting.get("forum.event_webhook_events")
  end

  teardown do
    SiteSetting.set("forum.event_webhook_url", @previous_url || "")
    SiteSetting.set(
      "forum.event_webhook_events",
      @previous_events || Community::DispatchForumEventWebhook::DEFAULT_EVENTS
    )
  end

  test "admin cannot persist a private event webhook URL" do
    patch admin_forum_settings_path, params: {
      settings: { "forum.event_webhook_url" => "http://127.0.0.1/internal" }
    }

    assert_redirected_to admin_forum_settings_path
    assert_setting_unchanged("forum.event_webhook_url", @previous_url)
  end

  test "admin event list rejects unknown names and canonicalizes supported names" do
    patch admin_forum_settings_path, params: {
      settings: { "forum.event_webhook_events" => "post.created,private.sentinel" }
    }
    assert_redirected_to admin_forum_settings_path
    assert_setting_unchanged("forum.event_webhook_events", @previous_events)

    patch admin_forum_settings_path, params: {
      settings: { "forum.event_webhook_events" => " post.created   topic.created post.created " }
    }
    assert_redirected_to admin_forum_settings_path
    assert_equal "post.created,topic.created", SiteSetting.get("forum.event_webhook_events")
  end

  private

  def assert_setting_unchanged(key, previous_value)
    current_value = SiteSetting.get(key)
    previous_value.nil? ? assert_nil(current_value) : assert_equal(previous_value, current_value)
  end
end

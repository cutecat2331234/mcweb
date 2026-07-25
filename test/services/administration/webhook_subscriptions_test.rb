# frozen_string_literal: true

require "test_helper"

class Administration::WebhookSubscriptionModelTest < ActiveSupport::TestCase
  test "validates url is public and event is known" do
    sub = Administration::WebhookSubscription.new(name: "x", url: "http://127.0.0.1/hook", event: "*")
    assert_not sub.valid?
    assert sub.errors[:url].present?

    sub = Administration::WebhookSubscription.new(name: "x", url: "https://example.com/hook", event: "not.an.event")
    assert_not sub.valid?
    assert sub.errors[:event].present?

    sub = Administration::WebhookSubscription.new(name: "x", url: "https://example.com/hook", event: "forum.post.created")
    assert sub.valid?
  end

  test "for_event matches exact event and wildcard, only active" do
    exact = Administration::WebhookSubscription.create!(name: "exact", url: "https://example.com/a", event: "forum.post.created")
    wild = Administration::WebhookSubscription.create!(name: "wild", url: "https://example.com/b", event: "*")
    Administration::WebhookSubscription.create!(name: "other", url: "https://example.com/c", event: "forum.topic.created")
    Administration::WebhookSubscription.create!(name: "inactive", url: "https://example.com/d", event: "*", active: false)

    ids = Administration::WebhookSubscription.for_event("forum.post.created").pluck(:id)
    assert_includes ids, exact.id
    assert_includes ids, wild.id
    assert_equal 2, ids.size
  end

  test "record_result! auto-disables after max failures" do
    sub = Administration::WebhookSubscription.create!(name: "x", url: "https://example.com/a", event: "*")
    (Administration::WebhookSubscription::MAX_FAILURES - 1).times { sub.record_result!(success: false, status: "500") }
    assert sub.active?
    sub.record_result!(success: false, status: "500")
    assert_not sub.reload.active?
    assert sub.disabled_at.present?
  end
end

class Administration::WebhookFanoutTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "publishing a catalog event enqueues delivery for matching subscription" do
    Administration::WebhookSubscription.create!(name: "wild", url: "https://example.com/hook", event: "*")
    category = Community::Category.create!(name: "Webhook", slug: "webhook-#{SecureRandom.hex(4)}")
    section = Community::Section.create!(
      category: category,
      name: "Public",
      slug: "webhook-public-#{SecureRandom.hex(4)}",
      position: 0
    )
    author = create_user
    topic = Community::Topic.create!(
      section: section,
      user: author,
      title: "Public topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: author,
      replies_count: 0
    )
    post = Community::Post.create!(
      topic: topic,
      user: author,
      floor_number: 1,
      body: "Public post",
      status: "published"
    )

    assert_enqueued_with(job: Administration::DeliverWebhookSubscriptionJob) do
      Mcweb::Events.publish("forum.post.created", topic: topic, post: post)
    end
  end

  test "no subscribers means no jobs enqueued" do
    assert_no_enqueued_jobs only: Administration::DeliverWebhookSubscriptionJob do
      Mcweb::Events.publish("forum.post.created", topic: nil, post: nil)
    end
  end

  test "delivery job marks subscription failed for an unreachable url" do
    sub = Administration::WebhookSubscription.create!(name: "x", url: "https://example.com/hook", event: "*")
    # Point at an unroutable URL and perform inline; safe_http_post returns nil.
    sub.update_column(:url, "http://127.0.0.1:1/none")
    payload = Administration::SerializeEventPayload.call(
      event: "identity.user.registered",
      payload: {}
    )
    Administration::DeliverWebhookSubscriptionJob.perform_now(sub.id, payload)
    assert_equal 1, sub.reload.failure_count
  end

  test "delivery job re-sanitizes its envelope and enforces the subscribed event" do
    sub = Administration::WebhookSubscription.create!(
      name: "minimal",
      url: "https://example.com/hook",
      event: "forum.post.created"
    )
    category = Community::Category.create!(
      name: "Queued webhook",
      slug: "queued-webhook-#{SecureRandom.hex(4)}"
    )
    section = Community::Section.create!(
      category: category,
      name: "Queued webhook",
      slug: "queued-webhook-section-#{SecureRandom.hex(4)}",
      position: 0
    )
    author = create_user
    topic = Community::Topic.create!(
      section: section,
      user: author,
      title: "Queued webhook topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: author,
      replies_count: 0
    )
    post = Community::Post.create!(
      topic: topic,
      user: author,
      floor_number: 1,
      body: "Queued webhook post",
      status: "published"
    )
    bodies = []
    payload = {
      "event" => "forum.post.created",
      "occurred_at" => Time.current.iso8601,
      "data" => {
        "topic" => { "id" => topic.public_id, "title" => "TITLE_SENTINEL" },
        "post" => {
          "id" => post.id,
          "topic_id" => topic.public_id,
          "body" => "BODY_SENTINEL"
        },
        "reason" => "REASON_SENTINEL"
      }
    }
    response = Data.define(:code, :body).new(code: "204", body: "")
    poster = lambda do |_uri, body:, **_options|
      bodies << body
      response
    end

    with_singleton_method(UrlSafety, :public_http_url?, ->(*) { true }) do
      with_singleton_method(UrlSafety, :safe_http_post, poster) do
        Administration::DeliverWebhookSubscriptionJob.perform_now(sub.id, payload)
        Administration::DeliverWebhookSubscriptionJob.perform_now(
          sub.id,
          payload.merge("event" => "forum.post.deleted")
        )
      end
    end

    assert_equal 1, bodies.size
    delivered = JSON.parse(bodies.first)
    assert_equal({ "id" => topic.public_id }, delivered.dig("data", "topic"))
    assert_equal(
      { "id" => post.id, "topic_id" => topic.public_id },
      delivered.dig("data", "post")
    )
    refute_match(/title|body|reason|SENTINEL/i, bodies.first)
  end

  private

  def with_singleton_method(object, method_name, replacement)
    original = object.method(method_name)
    object.define_singleton_method(method_name, replacement)
    yield
  ensure
    object.define_singleton_method(method_name, original)
  end
end

class Administration::SerializeEventPayloadTest < ActiveSupport::TestCase
  test "serializes known records to identifier-only invalidations" do
    category = Community::Category.find_or_create_by!(slug: "whk-cat") { |c| c.name = "W" }
    section = Community::Section.find_or_create_by!(category: category, slug: "whk-sec") do |s|
      s.name = "W"
      s.position = 0
    end
    author = create_user(username: "whkauthor")
    topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}", section: section, user: author,
      title: "Hook topic", status: "published", last_posted_at: Time.current, last_post_user: author, replies_count: 0
    )
    post = Community::Post.create!(topic: topic, user: author, floor_number: 1, body: "OP", status: "published")

    result = Administration::SerializeEventPayload.call(
      event: "forum.post.created",
      payload: {
        topic: topic,
        post: post,
        user: author,
        reason: "PRIVATE_REASON_SENTINEL",
        metadata: { body: "PRIVATE_BODY_SENTINEL" }
      }
    )
    assert_equal "forum.post.created", result["event"]
    assert_equal topic.public_id, result["data"]["topic"]["id"]
    assert_equal post.id, result["data"]["post"]["id"]
    assert_equal author.public_id, result["data"]["user"]["id"]
    refute_includes result.to_json, author.username
    refute_match(/title|body|username|reason|SENTINEL/i, result.to_json)
  end
end

class Administration::WebhookSubscriptionsAdminTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
    sign_in_as(@admin)
  end

  test "index renders" do
    get admin_system_webhook_subscriptions_path
    assert_response :success
  end

  test "admin can create, update and delete a subscription" do
    assert_difference -> { Administration::WebhookSubscription.count }, 1 do
      post admin_system_webhook_subscriptions_path, params: {
        webhook_subscription: { name: "Zapier", url: "https://example.com/hook", event: "forum.post.created", secret: "s3cret", active: true }
      }
    end
    assert_redirected_to admin_system_webhook_subscriptions_path
    sub = Administration::WebhookSubscription.order(:created_at).last
    assert_equal "Zapier", sub.name

    patch admin_system_webhook_subscription_path(sub), params: {
      webhook_subscription: { name: "Zapier2", url: sub.url, event: "*", secret: "", active: true }
    }
    assert_equal "Zapier2", sub.reload.name
    assert_equal "*", sub.event

    assert_difference -> { Administration::WebhookSubscription.count }, -1 do
      delete admin_system_webhook_subscription_path(sub)
    end
  end

  test "invalid private url is rejected" do
    assert_no_difference -> { Administration::WebhookSubscription.count } do
      post admin_system_webhook_subscriptions_path, params: {
        webhook_subscription: { name: "bad", url: "http://127.0.0.1/hook", event: "*" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "admin access alone cannot manage webhook subscriptions" do
    delete identity_session_path
    limited_admin = create_user(account_type: :admin)
    grant_permission(limited_admin, "admin.access")
    sign_in_as(limited_admin)

    get admin_system_webhook_subscriptions_path
    assert_response :redirect

    assert_no_difference -> { Administration::WebhookSubscription.count } do
      post admin_system_webhook_subscriptions_path, params: {
        webhook_subscription: { name: "Forbidden", url: "https://example.com/hook", event: "*" }
      }
    end
  end
end

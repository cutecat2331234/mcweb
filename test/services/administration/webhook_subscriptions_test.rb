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

    assert_enqueued_with(job: Administration::DeliverWebhookSubscriptionJob) do
      Mcweb::Events.publish("forum.post.created", topic: nil, post: nil)
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
    payload = Administration::SerializeEventPayload.call(event: "forum.post.created", payload: {})
    Administration::DeliverWebhookSubscriptionJob.perform_now(sub.id, payload)
    assert_equal 1, sub.reload.failure_count
  end
end

class Administration::SerializeEventPayloadTest < ActiveSupport::TestCase
  test "serializes known records to safe public fields" do
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

    result = Administration::SerializeEventPayload.call(event: "forum.post.created", payload: { topic: topic, post: post, user: author })
    assert_equal "forum.post.created", result["event"]
    assert_equal topic.public_id, result["data"]["topic"]["id"]
    assert_equal post.id, result["data"]["post"]["id"]
    assert_equal author.username, result["data"]["user"]["username"]
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
end

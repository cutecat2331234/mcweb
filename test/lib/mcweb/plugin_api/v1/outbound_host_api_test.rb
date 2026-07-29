# frozen_string_literal: true

require "test_helper"
require "mcweb/plugin_api/v1/host"

class Mcweb::PluginApi::V1::OutboundHostApiTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @audits = []
    @host = build_host("acme/outbound", audits: @audits)
  end

  test "host exposes versioned outbound facades and audits capabilities" do
    assert_respond_to @host, :notifications
    assert_respond_to @host, :mail
    assert_respond_to @host, :webhooks
    assert_respond_to @host, :storage

    result = @host.notifications.deliver(
      user: @user,
      notification_type: "release_ready",
      title: "Release ready",
      idempotency_key: "release-1"
    )

    assert_predicate result, :success?
    assert_equal "plugin.notifications.deliver", @audits.last
    assert_equal "notification", result.value.fetch("kind")
    assert_predicate result.value, :frozen?
  end

  test "notification delivery is idempotent and respects current recipient preference" do
    first = @host.notifications.deliver(
      user: @user,
      notification_type: "build_finished",
      title: "Build finished",
      body: "The build is ready.",
      metadata: { path: "/builds/1" },
      idempotency_key: "build-1"
    )
    second = @host.notifications.deliver(
      user: @user,
      notification_type: "build_finished",
      title: "Build finished",
      body: "The build is ready.",
      metadata: { path: "/builds/1" },
      idempotency_key: "build-1"
    )

    assert_predicate first, :success?
    assert_predicate second, :success?
    assert_equal first.value.fetch("public_id"), second.value.fetch("public_id")
    assert_equal true, second.value.fetch("idempotent")
    assert_equal 1, PluginOutboundDelivery.owned_by("acme/outbound").count

    type = "plugin.acme.outbound.build_finished"
    NotificationPreference.set!(@user, channel: "in_app", notification_type: type, enabled: false)
    PluginOutboundDeliveryJob.perform_now(first.value.fetch("public_id"))

    delivery = PluginOutboundDelivery.find_by!(public_id: first.value.fetch("public_id"))
    assert_equal "suppressed", delivery.status
    assert_equal 0, Notification.where(user: @user, notification_type: type).count
  end

  test "idempotency key rejects changed delivery input" do
    first = @host.mail.deliver(
      user: @user,
      notification_type: "receipt",
      subject: "First",
      text_body: "first body",
      idempotency_key: "mail-1"
    )
    conflict = @host.mail.deliver(
      user: @user,
      notification_type: "receipt",
      subject: "Changed",
      text_body: "changed body",
      idempotency_key: "mail-1"
    )

    assert_predicate first, :success?
    assert_predicate conflict, :failure?
    assert_equal "idempotency_conflict", conflict.code
  end

  test "mail delivery uses the preference policy and never exposes message content" do
    result = @host.mail.deliver(
      user: @user,
      notification_type: "monthly_report",
      subject: "Private subject",
      text_body: "private-body-token",
      html_body: "<strong>private-html-token</strong>",
      idempotency_key: "monthly-1"
    )
    assert_predicate result, :success?
    refute_includes result.to_h.to_json, "private-body-token"
    refute_includes result.to_h.to_json, "private-html-token"

    ActionMailer::Base.deliveries.clear
    PluginOutboundDeliveryJob.perform_now(result.value.fetch("public_id"))
    assert_equal 1, ActionMailer::Base.deliveries.length
    assert_equal "Private subject", ActionMailer::Base.deliveries.last.subject

    record = PluginOutboundDelivery.find_by!(public_id: result.value.fetch("public_id"))
    refute_includes record.encrypted_payload, "private-body-token"
    refute_includes record.encrypted_payload, "private-html-token"
  end

  test "webhook signs a stable envelope and retries without leaking secret" do
    captured = {}
    response = Struct.new(:code, :body).new("202", "accepted")
    poster = lambda do |uri, body:, headers:, **|
      captured[:uri] = uri.to_s
      captured[:body] = body
      captured[:headers] = headers
      response
    end

    UrlSafety.stub(:public_http_url?, true) do
      result = @host.webhooks.deliver(
        url: "https://hooks.example.test/plugin",
        event: "order_ready",
        data: { order: "ord_1" },
        secret: "a-very-private-signing-secret",
        idempotency_key: "webhook-1"
      )
      assert_predicate result, :success?
      refute_includes result.to_h.to_json, "a-very-private-signing-secret"
      refute_includes result.to_h.to_json, "hooks.example.test"

      UrlSafety.stub(:safe_http_post, poster) do
        PluginOutboundDeliveryJob.perform_now(result.value.fetch("public_id"))
      end

      delivery = PluginOutboundDelivery.find_by!(public_id: result.value.fetch("public_id"))
      assert_equal "succeeded", delivery.status
      assert_equal 202, delivery.last_http_status
      assert_equal "https://hooks.example.test/plugin", captured.fetch(:uri)
      envelope = JSON.parse(captured.fetch(:body))
      assert_equal "plugin.acme.outbound.order_ready", envelope.fetch("event")
      assert_equal({ "order" => "ord_1" }, envelope.fetch("data"))
      assert_match(/\Asha256=/, captured.fetch(:headers).fetch("X-McWeb-Signature"))
    end
  end

  test "webhook failures are retried with bounded diagnostics" do
    UrlSafety.stub(:public_http_url?, true) do
      result = @host.webhooks.deliver(
        url: "https://hooks.example.test/failure",
        event: "failed",
        data: {},
        secret: "a-very-private-signing-secret",
        idempotency_key: "webhook-retry",
        max_attempts: 2
      )
      UrlSafety.stub(:safe_http_post, nil) do
        PluginOutboundDeliveryJob.perform_now(result.value.fetch("public_id"))
      end

      delivery = PluginOutboundDelivery.find_by!(public_id: result.value.fetch("public_id"))
      assert_equal "retrying", delivery.status
      assert_equal "network_failure", delivery.last_error_code
      assert_equal 1, delivery.attempts
      assert delivery.next_attempt_at.future?
      refute_includes delivery.response_summary, "private"
    end
  end

  test "plugin namespaces cannot inspect another plugin delivery" do
    result = @host.notifications.deliver(
      user: @user,
      notification_type: "private",
      title: "Private",
      idempotency_key: "private-1"
    )
    other = build_host("other/plugin")

    hidden = other.notifications.find(public_id: result.value.fetch("public_id"))
    assert_predicate hidden, :failure?
    assert_equal "not_found", hidden.code
  end

  test "maintenance recovers timed out workers and terminally fails exhausted attempts" do
    retrying = create_notification_delivery("recoverable")
    exhausted = create_notification_delivery("exhausted")
    retrying.update_columns(
      status: "processing",
      attempts: 1,
      max_attempts: 3,
      updated_at: 20.minutes.ago
    )
    exhausted.update_columns(
      status: "processing",
      attempts: 2,
      max_attempts: 2,
      updated_at: 20.minutes.ago
    )
    clear_enqueued_jobs

    RecoverPluginOutboundDeliveriesJob.perform_now

    assert_equal "retrying", retrying.reload.status
    assert_equal "processing_timeout", retrying.last_error_code
    assert_equal "failed", exhausted.reload.status
    assert_equal "processing_timeout", exhausted.last_error_code
    assert exhausted.delivered_at.present?
    assert_enqueued_with(job: PluginOutboundDeliveryJob, args: [ retrying.public_id ])
  end

  test "maintenance requeues old queued and overdue retry deliveries" do
    queued = create_notification_delivery("lost-queued")
    retrying = create_notification_delivery("lost-retry")
    queued.update_columns(created_at: 10.minutes.ago, updated_at: 10.minutes.ago)
    retrying.update_columns(
      status: "retrying",
      attempts: 1,
      next_attempt_at: 10.minutes.ago,
      updated_at: 10.minutes.ago
    )
    clear_enqueued_jobs

    RecoverPluginOutboundDeliveriesJob.perform_now

    assert_enqueued_with(job: PluginOutboundDeliveryJob, args: [ queued.public_id ])
    assert_enqueued_with(job: PluginOutboundDeliveryJob, args: [ retrying.public_id ])
  end

  private

  def create_notification_delivery(idempotency_key)
    result = @host.notifications.deliver(
      user: @user,
      notification_type: "maintenance",
      title: "Maintenance",
      idempotency_key:
    )
    PluginOutboundDelivery.find_by!(public_id: result.value.fetch("public_id"))
  end

  def build_host(plugin_id, audits: nil)
    manifest = Mcweb::Plugins::Manifest.from_hash({
      id: plugin_id,
      name: plugin_id,
      version: "1.0.0",
      api_version: "1",
      capabilities: %w[
        plugin.mail.deliver
        plugin.mail.read
        plugin.notifications.deliver
        plugin.notifications.read
        plugin.storage.read
        plugin.storage.write
        plugin.webhooks.deliver
        plugin.webhooks.read
      ]
    })
    Mcweb::PluginApi::V1::Host.new(
      manifest:,
      event_bus: Mcweb::Events,
      capability_auditor: audits && ->(capability) { audits << capability }
    )
  end
end

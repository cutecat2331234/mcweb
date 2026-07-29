# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/devtools"

class CommerceFulfillmentReferencePluginContractTest < ActiveSupport::TestCase
  PLUGIN_ROOT = Pathname(__dir__).join("..").expand_path
  PLUGIN_ID = "examples/commerce_fulfillment"

  setup do
    Mcweb::Plugins.reset!
    PluginJobRun.where(owner_plugin_id: PLUGIN_ID).delete_all
    clear_enqueued_jobs
  end

  teardown do
    Mcweb::Plugins.reset!
    PluginJobRun.where(owner_plugin_id: PLUGIN_ID).delete_all
    clear_enqueued_jobs
  end

  test "paid-order event enqueues one idempotent fulfillment run" do
    Mcweb::Plugins.reload!(root: PLUGIN_ROOT)

    2.times do
      Mcweb::Events.publish(
        "commerce.order.paid",
        order: { public_id: "order-reference-one" }
      )
    end

    run = PluginJobRun.where(owner_plugin_id: PLUGIN_ID).sole
    assert_equal "fulfill", run.job_key
    assert_equal "fulfillment:order-reference-one:v1", run.idempotency_key
  end

  test "manifest and host catalog expose the documented commerce contracts" do
    manifest = Mcweb::Plugins::Manifest.load_file(PLUGIN_ROOT.join("mcweb_plugin.yml"))

    assert_includes manifest.capabilities, "commerce.events.read"
    assert_includes manifest.capabilities, "commerce.fulfillments.write"
    %w[
      commerce.order.paid
      commerce.fulfillment.dispatched
      commerce.fulfillment.retryable_failed
      commerce.fulfillment.failed
      commerce.fulfillment.completed
      commerce.fulfillment.cancelled
    ].each do |event|
      assert_includes Mcweb::Events::CATALOG, event
    end
  end

  test "direct fulfillment provider returns a stable external reference" do
    Mcweb::Plugins.reload!(root: PLUGIN_ROOT)

    result = Mcweb::Plugins.dispatch_fulfillment(
      provider_id: "#{PLUGIN_ID}:direct",
      request: {
        delivery_id: "delivery-reference-one",
        options: {}
      }
    )

    assert_equal "succeeded", result.fetch("status")
    assert_equal(
      "reference:delivery-reference-one",
      result.fetch("external_reference")
    )
  end

  test "temporary provider failure retries and succeeds without a second run" do
    Mcweb::Plugins.reload!(root: PLUGIN_ROOT)
    manifest = Mcweb::Plugins::Manifest.load_file(PLUGIN_ROOT.join("mcweb_plugin.yml"))
    host = Mcweb::PluginApi::V1::Host.new(manifest:, event_bus: Mcweb::Events)
    first = host.jobs.enqueue(
      job_key: "fulfill",
      arguments: {
        order_public_id: "order-reference-retry",
        fail_until_attempt: 1
      },
      idempotency_key: "fulfillment:order-reference-retry:v1"
    )
    duplicate = host.jobs.enqueue(
      job_key: "fulfill",
      arguments: {
        order_public_id: "order-reference-retry",
        fail_until_attempt: 1
      },
      idempotency_key: "fulfillment:order-reference-retry:v1"
    )

    assert_predicate first, :success?
    assert duplicate.value.fetch("idempotent")
    assert_equal first.value.fetch("public_id"), duplicate.value.fetch("public_id")

    PluginOwnedJob.perform_now(first.value.fetch("public_id"))
    run = PluginJobRun.find_by!(public_id: first.value.fetch("public_id"))
    assert_equal "retrying", run.status

    PluginOwnedJob.perform_now(run.public_id)
    assert_equal "succeeded", run.reload.status
    assert_equal 1, PluginJobRun.where(owner_plugin_id: PLUGIN_ID).count
  end
end

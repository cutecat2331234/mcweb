# frozen_string_literal: true

require "digest"
require "json"
require "stringio"
require "test_helper"
require "mcweb/plugin_api/v1/host"
require "mcweb/plugins/registry"
require "tmpdir"

class Mcweb::PluginApi::V1::JobsTest < ActiveSupport::TestCase
  class NullEventBus
    def publish(*)
      true
    end
  end

  setup do
    @root = Pathname(Dir.mktmpdir("mcweb-plugin-jobs"))
    Mcweb::Plugins.reset!
    clear_enqueued_jobs
  end

  teardown do
    Mcweb::Plugins.reset!
    clear_enqueued_jobs
    FileUtils.remove_entry(@root) if @root&.exist?
  end

  test "enqueue persists encrypted ownership metadata and exposes no argument values" do
    received = nil
    manifest, definition = register_plugin do |arguments, context|
      received = [ arguments, context ]
    end
    audits = []
    host = build_host(manifest, audits:)
    secret = "never-store-this-in-plaintext"

    result = host.jobs.enqueue(
      job_key: "deliver",
      arguments: {
        recipient_id: SecureRandom.uuid,
        message: secret
      },
      idempotency_key: "delivery:one"
    )

    assert_predicate result, :success?
    run = PluginJobRun.find_by!(public_id: result.value.fetch("public_id"))
    assert_equal "acme/jobs", run.owner_plugin_id
    assert_equal "deliver", run.job_key
    assert_equal 2, run.payload_digest_version
    assert_equal 0, run.requested_wait_seconds
    canonical_payload = JSON.generate(
      {
        "plugin_id" => run.owner_plugin_id,
        "plugin_version" => run.plugin_version,
        "job_key" => run.job_key,
        "contribution_schema_version" => run.contribution_schema_version,
        "declaration_digest" => run.declaration_digest,
        "arguments" => run.arguments.sort.to_h,
        "idempotency_key" => run.idempotency_key,
        "wait_seconds" => run.requested_wait_seconds
      }
    )
    refute_equal Digest::SHA256.hexdigest(canonical_payload), run.payload_digest
    refute_includes run.encrypted_arguments, secret
    refute_includes result.to_h.to_json, secret
    refute_includes enqueued_jobs.map(&:inspect).join, secret
    refute_includes result.value.keys, "arguments"
    assert_equal [ "plugin.jobs.enqueue" ], audits

    run.update!(last_enqueue_error_code: "enqueue_failed")
    PluginOwnedJob.perform_now(run.public_id)
    run.reload
    assert_equal "succeeded", run.status
    assert_equal 1, run.attempts
    assert_nil run.last_enqueue_error_code
    arguments, context = received
    assert_predicate arguments, :frozen?
    assert_predicate context, :frozen?
    assert_equal secret, arguments.fetch("message")
    assert_equal run.public_id, context.run_public_id
    assert_raises(FrozenError) { arguments["message"] = "changed" }
    assert_equal definition.api.jobs.declaration.digest, host.jobs.declaration.digest
  end

  test "idempotency conflicts arbitrary classes and cross-plugin access are rejected" do
    manifest, = register_plugin
    host = build_host(manifest)
    arguments = {
      recipient_id: SecureRandom.uuid,
      message: "stable"
    }
    first = host.jobs.enqueue(
      job_key: "deliver",
      arguments:,
      idempotency_key: "delivery:same"
    )
    duplicate = host.jobs.enqueue(
      job_key: "deliver",
      arguments:,
      idempotency_key: "delivery:same"
    )
    conflict = host.jobs.enqueue(
      job_key: "deliver",
      arguments: arguments.merge(message: "different"),
      idempotency_key: "delivery:same"
    )

    assert_predicate first, :success?
    assert_predicate duplicate, :success?
    assert duplicate.value.fetch("idempotent")
    assert_equal first.value.fetch("public_id"), duplicate.value.fetch("public_id")
    assert_equal "idempotency_conflict", conflict.code
    assert_equal 1, PluginJobRun.where(owner_plugin_id: "acme/jobs").count

    other_manifest = write_plugin(
      plugin_id: "other/jobs",
      version: "1.0.0",
      directory_name: "other"
    )
    other = build_host(other_manifest)
    assert_equal "not_found", other.jobs.find(public_id: first.value.fetch("public_id")).code
    assert_equal "not_found", other.jobs.cancel(public_id: first.value.fetch("public_id")).code
    assert_equal(
      "job_not_declared",
      host.jobs.enqueue(
        job_key: "other/jobs.deliver",
        arguments:,
        idempotency_key: "delivery:cross"
      ).code
    )
    assert_raises(ArgumentError) do
      host.jobs.enqueue(
        job_key: "deliver",
        arguments:,
        idempotency_key: "delivery:class",
        job_class: Kernel
      )
    end
  end

  test "handler failures retry with sanitized diagnostics and then succeed" do
    calls = 0
    manifest, = register_plugin(max_attempts: 2, retry_wait_seconds: 0) do |arguments,|
      calls += 1
      raise "payload=#{arguments.fetch('message')}" if calls == 1
    end
    host = build_host(manifest)
    secret = "retry-secret"
    result = host.jobs.enqueue(
      job_key: "deliver",
      arguments: {
        recipient_id: SecureRandom.uuid,
        message: secret
      },
      idempotency_key: "delivery:retry"
    )
    public_id = result.value.fetch("public_id")

    PluginOwnedJob.perform_now(public_id)
    run = PluginJobRun.find_by!(public_id:)
    assert_equal "retrying", run.status
    assert_equal 1, run.attempts
    assert_equal "handler_failed", run.last_error_code
    refute_includes Mcweb::Plugins.diagnostics.to_json, secret

    PluginOwnedJob.perform_now(public_id)
    run.reload
    assert_equal "succeeded", run.status
    assert_equal 2, run.attempts
    assert_equal 2, calls
  end

  test "unavailable and incompatible releases pause without consuming an attempt" do
    manifest, = register_plugin(max_attempts: 1)
    host = build_host(manifest)
    unavailable = host.jobs.enqueue(
      job_key: "deliver",
      arguments: {
        recipient_id: SecureRandom.uuid,
        message: "pause"
      },
      idempotency_key: "delivery:paused"
    )
    public_id = unavailable.value.fetch("public_id")

    Mcweb::Plugins.reset!
    PluginOwnedJob.perform_now(public_id)
    run = PluginJobRun.find_by!(public_id:)
    assert_equal "paused", run.status
    assert_equal 0, run.attempts
    assert_equal "plugin_unavailable", run.last_error_code

    manifest, = register_plugin(manifest:, max_attempts: 1)
    host = build_host(manifest)
    assert_predicate host.jobs.resume(public_id:), :success?
    PluginOwnedJob.perform_now(public_id)
    assert_equal "succeeded", run.reload.status
    assert_equal 1, run.attempts

    incompatible = host.jobs.enqueue(
      job_key: "deliver",
      arguments: {
        recipient_id: SecureRandom.uuid,
        message: "version"
      },
      idempotency_key: "delivery:version"
    )
    Mcweb::Plugins.reset!
    version_two = write_plugin(plugin_id: "acme/jobs", version: "2.0.0", directory_name: "v2")
    register_plugin(manifest: version_two)
    PluginOwnedJob.perform_now(incompatible.value.fetch("public_id"))
    versioned_run = PluginJobRun.find_by!(public_id: incompatible.value.fetch("public_id"))
    assert_equal "paused", versioned_run.status
    assert_equal 0, versioned_run.attempts
    assert_equal "incompatible_job", versioned_run.last_error_code
  end

  test "an expired lease is reclaimed under a new attempt" do
    calls = 0
    manifest, = register_plugin(max_attempts: 2) { calls += 1 }
    host = build_host(manifest)
    result = host.jobs.enqueue(
      job_key: "deliver",
      arguments: {
        recipient_id: SecureRandom.uuid,
        message: "lease"
      },
      idempotency_key: "delivery:lease"
    )
    run = PluginJobRun.find_by!(public_id: result.value.fetch("public_id"))
    run.update!(
      status: "running",
      attempts: 1,
      started_at: 2.minutes.ago,
      lease_expires_at: 1.minute.ago
    )

    PluginOwnedJob.perform_now(run.public_id)

    assert_equal "succeeded", run.reload.status
    assert_equal 2, run.attempts
    assert_equal 1, calls
  end

  test "unexpected host failures return and log only fixed safe metadata" do
    manifest, = register_plugin
    host = build_host(manifest)
    log_output = StringIO.new
    logger = ActiveSupport::Logger.new(log_output)
    secret = "never-log-this-message"
    idempotency_key = "delivery:never-log-this-key"
    store = host.jobs.instance_variable_get(:@store)
    original_logger = Rails.logger
    original_enqueue = store.method(:enqueue)

    store.define_singleton_method(:enqueue) { |**| raise RuntimeError, secret }
    Rails.logger = logger
    result = host.jobs.enqueue(
      job_key: "deliver",
      arguments: {
        recipient_id: SecureRandom.uuid,
        message: secret
      },
      idempotency_key:
    )

    assert_equal "host_error", result.code
    assert_equal "plugin jobs operation failed", result.error
  ensure
    store&.define_singleton_method(:enqueue, original_enqueue) if original_enqueue
    Rails.logger = original_logger if original_logger

    if log_output
      logged = log_output.string
      assert_includes logged, "plugin_job.host_error"
      assert_includes logged, '"plugin_id":"acme/jobs"'
      assert_includes logged, '"job_key":"deliver"'
      assert_includes logged, '"error_class":"RuntimeError"'
      refute_includes logged, secret
      refute_includes logged, idempotency_key
    end
  end

  private

  def register_plugin(
    manifest: nil,
    max_attempts: 3,
    retry_wait_seconds: 5,
    &handler
  )
    manifest ||= write_plugin(
      plugin_id: "acme/jobs",
      version: "1.0.0",
      directory_name: SecureRandom.hex(3),
      max_attempts:,
      retry_wait_seconds:
    )
    definition = Mcweb::Plugins.register(manifest) do |plugin|
      plugin.job("deliver", &(handler || ->(*) { }))
    end
    Mcweb::Plugins.boot!
    [ manifest, definition ]
  end

  def build_host(manifest, audits: nil)
    Mcweb::PluginApi::V1::Host.new(
      manifest:,
      event_bus: NullEventBus.new,
      capability_auditor: audits && ->(capability) { audits << capability }
    )
  end

  def write_plugin(
    plugin_id:,
    version:,
    directory_name:,
    max_attempts: 3,
    retry_wait_seconds: 5
  )
    directory = @root.join(directory_name)
    FileUtils.mkdir_p(directory.join("config"))
    document = {
      "schema_version" => "1",
      "jobs" => {
        "deliver" => {
          "max_attempts" => max_attempts,
          "retry_wait_seconds" => retry_wait_seconds,
          "lease_seconds" => 60,
          "arguments" => {
            "$schema" => Mcweb::Plugins::JobContribution::DRAFT_URI,
            "type" => "object",
            "additionalProperties" => false,
            "required" => %w[recipient_id message],
            "properties" => {
              "recipient_id" => { "type" => "string", "format" => "uuid" },
              "message" => { "type" => "string", "maxLength" => 1_024 }
            }
          }
        }
      }
    }
    File.write(directory.join("config/jobs.yml"), YAML.dump(document))
    File.write(
      directory.join("mcweb_plugin.yml"),
      YAML.dump(
        "id" => plugin_id,
        "name" => "Jobs",
        "version" => version,
        "api_version" => "1",
        "capabilities" => %w[plugin.jobs.read plugin.jobs.enqueue],
        "contributions" => { "jobs" => "config/jobs.yml" }
      )
    )
    Mcweb::Plugins::Manifest.load_file(directory.join("mcweb_plugin.yml"))
  end
end
